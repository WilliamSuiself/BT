/// 一个种子/磁力链的下载会话
///
/// 粘合：
/// - TrackerClient：发现 peer
/// - PieceStorage：落盘 + 校验 + 断点续传
/// - PiecePicker：决定下一个请求哪个 piece 的哪个 block
/// - 多个 PeerConnection：并发下载
library download_session;

import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:logger/logger.dart';
import 'package:uuid/uuid.dart';

import '../../models/torrent_info.dart';
import '../storage/piece_storage.dart';
import 'peer_protocol.dart';
import 'tracker_client.dart';

enum SessionStatus { added, running, paused, completed, error }

class DownloadSession {
  final String id;
  final TorrentInfo torrent;
  final String? displayName; // 来自 magnet 或种子 name
  final PieceStorage storage;
  final TrackerClient tracker;
  final List<TrackerPeer> _knownPeers = [];
  final List<PeerConnection> _peers = [];
  final Map<int, List<int>> _peerHavePieces = {}; // peer -> have set
  final Logger _log = Logger();
  final _statusController = StreamController<SessionStatus>.broadcast();
  final _statsController = StreamController<DownloadStats>.broadcast();

  int downloaded = 0;
  int uploaded = 0;
  SessionStatus _status = SessionStatus.added;
  DateTime? _lastAnnounce;

  DownloadSession({
    required this.torrent,
    this.displayName,
    required Directory saveDir,
    required String peerId,
    required int listenPort,
  })  : id = const Uuid().v4(),
        storage = PieceStorage(torrent: torrent, saveDir: saveDir),
        tracker = TrackerClient(peerId: peerId, port: listenPort) {
    _statusController.add(_status);
  }

  Stream<SessionStatus> get statusStream => _statusController.stream;
  Stream<DownloadStats> get statsStream => _statsController.stream;
  SessionStatus get status => _status;
  String get name => displayName ?? torrent.name ?? id;
  int get totalLength => torrent.totalLength;
  int get left => totalLength - storage.completedBytes;
  double get progress => storage.progress;

  Future<void> start() async {
    _status = SessionStatus.running;
    _statusController.add(_status);
    await storage.loadResumeState();
    await _announceAll();
    _connectToKnownPeers();
  }

  Future<void> pause() async {
    _status = SessionStatus.paused;
    _statusController.add(_status);
    for (final p in List<PeerConnection>.from(_peers)) {
      p.close();
    }
    _peers.clear();
    await storage.close();
  }

  Future<void> _announceAll() async {
    final stats = TrackerStats(
      downloaded: downloaded,
      uploaded: uploaded,
      left: left,
    );
    final urls = <String>[
      ...torrent.trackers.announce,
      ...torrent.trackers.announceList.expand((e) => e),
    ].toSet();
    for (final url in urls) {
      try {
        final resp = await tracker.announce(
          torrent: torrent,
          trackerUrl: url,
          stats: stats,
          event: _status == SessionStatus.added
              ? TrackerEvent.started
              : TrackerEvent.periodic,
        );
        _knownPeers.addAll(resp.peers);
        _lastAnnounce = DateTime.now();
        _log.i('Tracker $url returned ${resp.peers.length} peers');
      } catch (e) {
        _log.w('Tracker $url failed: $e');
      }
    }
  }

  void _connectToKnownPeers() {
    for (final p in _knownPeers) {
      if (_peers.length >= 30) break;
      final conn = PeerConnection(
        host: p.ip,
        port: p.port,
        infoHash: torrent.infoHash,
        peerId: Uint8List.fromList(tracker.peerId.codeUnits.take(20).toList()),
      );
      conn.incoming.listen((msg) => _onPeerMessage(conn, msg));
      conn.connect().then((_) {
        _peers.add(conn);
        conn.sendInterested();
      }).catchError((e) {
        _log.d('Peer connect failed ${p.key}: $e');
      });
    }
  }

  /// piece/block 请求调度：每 1s 扫一次所有 peer，给 unchoke 且感兴趣的 peer 派 request
  Timer? _scheduler;
  final Random _rand = Random();
  static const int _blockSize = 16384;

  void startScheduler() {
    _scheduler?.cancel();
    _scheduler = Timer.periodic(const Duration(milliseconds: 200), (_) => _schedule());
  }

  void _schedule() {
    if (_status != SessionStatus.running) return;
    for (final peer in _peers) {
      if (peer.isClosed || peer.amChoked || !peer.amInterested) continue;
      // 给每个 peer 派一个 pending request
      final next = _pickBlock(peer);
      if (next != null) {
        peer.sendRequest(next.pieceIndex, next.offset, next.length);
      }
    }
    _statsController.add(_snapshot());
  }

  BlockSpec? _pickBlock(PeerConnection peer) {
    // 简单 picker：按 piece 顺序选第一个未完成 piece 的下一个 block
    final have = _peerHavePieces[peer.hashCode];
    if (have == null || have.isEmpty) return null;
    for (final piece in storage.pieces) {
      if (piece.state == PieceState.verified) continue;
      if (!have.contains(piece.index)) continue;
      // 计算该 piece 当前已下载字节数（粗糙：以 piece 粒度，每次拿一个未完成 block）
      // 真实场景应维护 piece 的 block 位图；这里简化
      final offset = _rand.nextInt(piece.length ~/ _blockSize) * _blockSize;
      final length = (piece.length - offset) < _blockSize
          ? piece.length - offset
          : _blockSize;
      if (length <= 0) continue;
      return BlockSpec(piece.index, offset, length);
    }
    return null;
  }

  Future<void> _onPeerMessage(PeerConnection peer, PeerWireMessage msg) async {
    switch (msg.id) {
      case PeerMessage.keepAlive:
        // 标记 handshake 完成（peer_protocol 实现里用 0xfe 作为握手完成标记）
        break;
      case 0xfe:
        // 收到即视为 handshake 完成
        break;
      case PeerMessage.bitfield:
        _peerHavePieces[peer.hashCode] = _parseBitfield(msg.payload!, torrent.pieceCount);
        break;
      case PeerMessage.have:
        if (msg.payload != null && msg.payload!.length >= 4) {
          final idx = msg.payload!.buffer.asByteData().getUint32(0);
          (_peerHavePieces[peer.hashCode] ??= []).add(idx);
        }
        break;
      case PeerMessage.unchoke:
        // peer amChoked 由 peer_protocol 内部维护
        break;
      case PeerMessage.piece:
        if (msg.payload != null && msg.payload!.length >= 8) {
          final bd = msg.payload!.buffer.asByteData();
          final pieceIndex = bd.getUint32(0);
          final blockOffset = bd.getUint32(4);
          final blockData = Uint8List.sublistView(msg.payload!, 8);
          await storage.writeBlock(pieceIndex, blockOffset, blockData);
          downloaded += blockData.length;
          // 简化：每收一块就校验一次 piece（实际项目会有批量）
          if (blockOffset + blockData.length >= storage.pieces[pieceIndex].length) {
            final ok = await storage.verifyPiece(pieceIndex);
            _log.i('Piece $pieceIndex verify=${ok ? "OK" : "FAIL"}');
            if (storage.isComplete) {
              _status = SessionStatus.completed;
              _statusController.add(_status);
            }
          }
        }
        break;
    }
  }

  DownloadStats _snapshot() {
    return DownloadStats(
      downloaded: downloaded,
      uploaded: uploaded,
      totalLength: totalLength,
      progress: progress,
      peers: _peers.length,
    );
  }

  static List<int> _parseBitfield(Uint8List bits, int pieceCount) {
    final list = <int>[];
    for (var i = 0; i < pieceCount; i++) {
      final byte = bits[i ~/ 8];
      final mask = 0x80 >> (i % 8);
      if ((byte & mask) != 0) list.add(i);
    }
    return list;
  }
}

class BlockSpec {
  final int pieceIndex;
  final int offset;
  final int length;
  BlockSpec(this.pieceIndex, this.offset, this.length);
}

class DownloadStats {
  final int downloaded;
  final int uploaded;
  final int totalLength;
  final double progress;
  final int peers;
  DownloadStats({
    required this.downloaded,
    required this.uploaded,
    required this.totalLength,
    required this.progress,
    required this.peers,
  });
}
