/// Tracker 客户端（HTTP/HTTPS + UDP，BEP-3 / BEP-15）
library tracker_client;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import '../../models/torrent_info.dart';
import '../bencode/bencode.dart';

/// 一个 Tracker 返回的 peer
class TrackerPeer {
  final String ip;
  final int port;
  final String? peerId; // compact 模式下可能没有
  TrackerPeer(this.ip, this.port, [this.peerId]);
  String get key => '$ip:$port';
}

/// Tracker announce 响应
class TrackerResponse {
  final int interval; // 多久后再 announce
  final int? minInterval;
  final int? complete; // seeder 数
  final int? incomplete; // leecher 数
  final List<TrackerPeer> peers;
  final String? warning;
  final String? failureReason;
  final String? trackerId; // BEP-15

  TrackerResponse({
    required this.interval,
    this.minInterval,
    this.complete,
    this.incomplete,
    required this.peers,
    this.warning,
    this.failureReason,
    this.trackerId,
  });
}

/// Tracker 事件
enum TrackerEvent { started, stopped, completed, periodic }

/// 统计上报给 tracker
class TrackerStats {
  final int downloaded;
  final int uploaded;
  final int left; // 还剩多少字节
  TrackerStats({required this.downloaded, required this.uploaded, required this.left});
}

class TrackerClient {
  final String peerId; // 20 字节
  final int port; // 我们监听的端口
  final Duration timeout;

  TrackerClient({required this.peerId, required this.port, this.timeout = const Duration(seconds: 15)});

  Future<TrackerResponse> announce({
    required TorrentInfo torrent,
    required String trackerUrl,
    required TrackerStats stats,
    TrackerEvent event = TrackerEvent.started,
    String? trackerId,
  }) async {
    if (trackerUrl.startsWith('udp:')) {
      return _announceUdp(
        torrent: torrent,
        url: trackerUrl,
        stats: stats,
        event: event,
        trackerId: trackerId,
      );
    } else if (trackerUrl.startsWith('http:') || trackerUrl.startsWith('https:')) {
      return _announceHttp(
        torrent: torrent,
        url: trackerUrl,
        stats: stats,
        event: event,
        trackerId: trackerId,
      );
    } else {
      throw TrackerException('不支持的 tracker 协议: $trackerUrl');
    }
  }

  // -------- HTTP / HTTPS --------

  Future<TrackerResponse> _announceHttp({
    required TorrentInfo torrent,
    required String url,
    required TrackerStats stats,
    required TrackerEvent event,
    String? trackerId,
  }) async {
    final infoHashEncoded = _urlEncodeBytes(torrent.infoHash);
    final params = {
      'info_hash': infoHashEncoded,
      'peer_id': _urlEncodeBytes(_peerIdBytes),
      'port': port.toString(),
      'uploaded': stats.uploaded.toString(),
      'downloaded': stats.downloaded.toString(),
      'left': stats.left.toString(),
      'compact': '1',
      'event': _eventName(event),
      if (trackerId != null) 'trackerid': trackerId,
    };
    final uri = Uri.parse(url).replace(queryParameters: params);

    final client = HttpClient()..connectionTimeout = timeout;
    try {
      final req = await client.getUrl(uri);
      final resp = await req.close().timeout(timeout);
      final body = await resp.fold<List<int>>([], (acc, b) => acc..addAll(b));
      if (resp.statusCode < 200 || resp.statusCode >= 300) {
        throw TrackerException('HTTP ${resp.statusCode}: ${resp.statusCode}');
      }
      return _parseTrackerResponse(Uint8List.fromList(body));
    } finally {
      client.close(force: true);
    }
  }

  // -------- UDP --------

  /// BEP-15 状态机
  Future<TrackerResponse> _announceUdp({
    required TorrentInfo torrent,
    required String url,
    required TrackerStats stats,
    required TrackerEvent event,
    String? trackerId,
  }) async {
    final uri = Uri.parse(url);
    final conn = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
    try {
      final addr = InternetAddress(uri.host);
      final port = uri.port;
      final transactionId = _randomTransactionId();

      // 1) Connect 请求 (magic=0x41727101980, action=0, tx)
      final connectReq = Uint8List(16);
      _writeUint64(connectReq.buffer, 0, 0x41727101980);
      _writeUint32(connectReq.buffer, 8, 0); // connect
      _writeUint32(connectReq.buffer, 12, transactionId);
      conn.send(connectReq, addr, port);
      final connectResp = await _recvAction(conn, 0, transactionId, timeout);
      // connection_id 在前 8 字节
      final connId = connectResp.sublist(0, 8);

      // 2) Announce 请求
      final announceReq = Uint8List(98);
      // connection_id
      for (var i = 0; i < 8; i++) {
        announceReq[i] = connId[i];
      }
      _writeUint32(announceReq.buffer, 8, 1); // action=announce
      _writeUint32(announceReq.buffer, 12, transactionId);
      // info_hash (20)
      announceReq.sublist(16, 36).setRange(0, 20, torrent.infoHash);
      // peer_id (20)
      announceReq.sublist(36, 56).setRange(0, 20, _peerIdBytes);
      _writeUint64(announceReq.buffer, 56, stats.downloaded);
      _writeUint64(announceReq.buffer, 64, stats.left);
      _writeUint64(announceReq.buffer, 72, stats.uploaded);
      _writeUint32(announceReq.buffer, 80, _eventCode(event));
      _writeUint32(announceReq.buffer, 84, 0); // IP address (0)
      _writeUint32(announceReq.buffer, 88, _randomKey());
      _writeUint32(announceReq.buffer, 92, -1); // num_want (default)
      _writeUint16(announceReq.buffer, 96, port); // port

      conn.send(announceReq, addr, port);
      final announceResp = await _recvAction(conn, 1, transactionId, timeout);

      // 解析 announce resp: action(4) + tx(4) + interval(4) + leechers(4) + seeders(4) + peers(6*N)
      final interval = _readUint32(announceResp.buffer, 8);
      final leechers = _readUint32(announceResp.buffer, 12);
      final seeders = _readUint32(announceResp.buffer, 16);
      final peers = <TrackerPeer>[];
      var offset = 20;
      while (offset + 6 <= announceResp.length) {
        final ip = '${announceResp[offset]}.${announceResp[offset + 1]}.'
            '${announceResp[offset + 2]}.${announceResp[offset + 3]}';
        final p = _readUint16(announceResp.buffer, offset + 4);
        peers.add(TrackerPeer(ip, p));
        offset += 6;
      }
      return TrackerResponse(
        interval: interval,
        complete: seeders,
        incomplete: leechers,
        peers: peers,
      );
    } finally {
      conn.close();
    }
  }

  // -------- Helpers --------

  Uint8List get _peerIdBytes {
    // ASCII 编码的 20 字节 peer id
    return Uint8List.fromList(peerId.codeUnits.take(20).toList());
  }

  String _eventName(TrackerEvent e) {
    switch (e) {
      case TrackerEvent.started:
        return 'started';
      case TrackerEvent.stopped:
        return 'stopped';
      case TrackerEvent.completed:
        return 'completed';
      case TrackerEvent.periodic:
        return '';
    }
  }

  int _eventCode(TrackerEvent e) {
    switch (e) {
      case TrackerEvent.started:
        return 2;
      case TrackerEvent.stopped:
        return 3;
      case TrackerEvent.completed:
        return 1;
      case TrackerEvent.periodic:
        return 0;
    }
  }

  TrackerResponse _parseTrackerResponse(Uint8List body) {
    final decoded = BencodeDecoder(body).decode();
    if (decoded is! Map) {
      throw TrackerException('Tracker 响应不是字典');
    }
    final failure = decoded.getUtf8('failure reason');
    if (failure != null && failure.isNotEmpty) {
      throw TrackerException('Tracker 报错: $failure');
    }
    final warning = decoded.getUtf8('warning message');
    final interval = decoded.getInt('interval') ?? 1800;
    final minInterval = decoded.getInt('min interval');
    final complete = decoded.getInt('complete');
    final incomplete = decoded.getInt('incomplete');
    final trackerId = decoded.getUtf8('tracker id');

    final peers = <TrackerPeer>[];
    final peersRaw = decoded.getBytes('peers');
    if (peersRaw != null) {
      // compact: 6 字节 / peer
      var offset = 0;
      while (offset + 6 <= peersRaw.length) {
        final ip = '${peersRaw[offset]}.${peersRaw[offset + 1]}.'
            '${peersRaw[offset + 2]}.${peersRaw[offset + 3]}';
        final port = (peersRaw[offset + 4] << 8) | peersRaw[offset + 5];
        peers.add(TrackerPeer(ip, port));
        offset += 6;
      }
    } else {
      // model: 字典列表
      final list = decoded.getList('peers');
      if (list != null) {
        for (final e in list) {
          if (e is Map) {
            final ip = e.getUtf8('ip');
            final port = e.getInt('port');
            final pid = e.getUtf8('peer id');
            if (ip != null && port != null) {
              peers.add(TrackerPeer(ip, port, pid));
            }
          }
        }
      }
    }
    return TrackerResponse(
      interval: interval,
      minInterval: minInterval,
      complete: complete,
      incomplete: incomplete,
      peers: peers,
      warning: warning,
      trackerId: trackerId,
    );
  }

  static int _randomTransactionId() => Random().nextInt(0x7fffffff);
  static int _randomKey() => Random().nextInt(0x7fffffff);

  static Future<Uint8List> _recvAction(
      RawDatagramSocket conn, int action, int transactionId, Duration timeout) async {
    final completer = Completer<Uint8List>();
    Timer? timer;
    conn.listen((e) {
      if (e == RawSocketEvent.read) {
        final d = conn.receive();
        if (d != null && !completer.isCompleted) {
          final recvAction = _readUint32(d.data.buffer, 0);
          final recvTx = _readUint32(d.data.buffer, 4);
          if (recvAction == action && recvTx == transactionId) {
            timer?.cancel();
            completer.complete(d.data);
          }
        }
      }
    });
    timer = Timer(timeout, () {
      if (!completer.isCompleted) completer.completeError(TrackerException('UDP 超时'));
    });
    return completer.future;
  }

  static void _writeUint16(ByteBuffer b, int offset, int v) {
    b.asUint8List(offset, 2).setRange(0, 2, [(v >> 8) & 0xff, v & 0xff]);
  }

  static void _writeUint32(ByteBuffer b, int offset, int v) {
    b.asUint8List(offset, 4).setRange(
        0, 4,
        [(v >> 24) & 0xff, (v >> 16) & 0xff, (v >> 8) & 0xff, v & 0xff]);
  }

  static void _writeUint64(ByteBuffer b, int offset, int v) {
    b.asUint8List(offset, 8).setRange(0, 8, [
      (v >> 56) & 0xff,
      (v >> 48) & 0xff,
      (v >> 40) & 0xff,
      (v >> 32) & 0xff,
      (v >> 24) & 0xff,
      (v >> 16) & 0xff,
      (v >> 8) & 0xff,
      v & 0xff,
    ]);
  }

  static int _readUint16(ByteBuffer b, int offset) {
    final l = b.asUint8List(offset, 2);
    return (l[0] << 8) | l[1];
  }

  static int _readUint32(ByteBuffer b, int offset) {
    final l = b.asUint8List(offset, 4);
    return (l[0] << 24) | (l[1] << 16) | (l[2] << 8) | l[3];
  }
}

class TrackerException implements Exception {
  final String message;
  TrackerException(this.message);
  @override
  String toString() => 'TrackerException: $message';
}

/// URL 编码 BT 字节串：每个 byte 转 %XX
String _urlEncodeBytes(Uint8List bytes) {
  final sb = StringBuffer();
  for (final b in bytes) {
    if ((b >= 0x30 && b <= 0x39) ||
        (b >= 0x41 && b <= 0x5a) ||
        (b >= 0x61 && b <= 0x7a) ||
        b == 0x2d || b == 0x5f || b == 0x2e || b == 0x7e) {
      sb.writeCharCode(b);
    } else {
      sb.write('%${b.toRadixString(16).toUpperCase().padLeft(2, '0')}');
    }
  }
  return sb.toString();
}
