/// BitTorrent Peer Wire Protocol（BEP-3 + BEP-10 Extension Protocol）
///
/// 协议格式：
/// - 握手：长度固定 68 字节 = pstrlen(1) + pstr(19) + reserved(8) + info_hash(20) + peer_id(20)
///   pstr = "BitTorrent protocol"
/// - 普通消息：长度(4 BE) + id(1) + payload
/// - keep-alive：长度=0 无 id
/// - 扩展：reserved 第 5 字节（0-index 第 20 字节）置 1 表示支持 BEP-10
library peer_protocol;

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

/// Peer Wire 消息 id
class PeerMessage {
  static const int choke = 0;
  static const int unchoke = 1;
  static const int interested = 2;
  static const int notInterested = 3;
  static const int have = 4;
  static const int bitfield = 5;
  static const int request = 6;
  static const int piece = 7;
  static const int cancel = 8;
  static const int port = 9; // DHT port
  static const int extended = 20; // BEP-10
  static const int keepAlive = -1;
}

/// 一次握手包
class PeerHandshake {
  static const String protocolString = 'BitTorrent protocol';
  static const int handshakeLength = 68;

  final Uint8List infoHash;
  final Uint8List peerId;
  final Uint8List reserved;

  PeerHandshake({
    required this.infoHash,
    required this.peerId,
    Uint8List? reserved,
  }) : reserved = reserved ?? Uint8List(8);

  /// 设置 reserved 的扩展位（BEP-10）
  void enableExtension() {
    reserved[5] |= 0x10; // 第 20 字节（0-index 第 5）的最低位
  }

  Uint8List encode() {
    final buf = Uint8List(handshakeLength);
    buf[0] = protocolString.length;
    buf.setRange(1, 20, protocolString.codeUnits);
    buf.setRange(20, 28, reserved);
    buf.setRange(28, 48, infoHash);
    buf.setRange(48, 68, peerId);
    return buf;
  }

  static PeerHandshake? tryDecode(Uint8List data) {
    if (data.length < handshakeLength) return null;
    if (data[0] != 19) return null;
    final pstr = String.fromCharCodes(data.sublist(1, 20));
    if (pstr != protocolString) return null;
    return PeerHandshake(
      infoHash: Uint8List.fromList(data.sublist(28, 48)),
      peerId: Uint8List.fromList(data.sublist(48, 68)),
      reserved: Uint8List.fromList(data.sublist(20, 28)),
    );
  }
}

/// 单条 peer 消息
class PeerWireMessage {
  final int id; // -1 = keep-alive
  final Uint8List? payload;

  PeerWireMessage(this.id, [this.payload]);

  Uint8List encode() {
    if (id == PeerMessage.keepAlive) {
      return Uint8List(4);
    }
    final p = payload ?? Uint8List(0);
    final buf = Uint8List(4 + 1 + p.length);
    final len = 1 + p.length;
    buf[0] = (len >> 24) & 0xff;
    buf[1] = (len >> 16) & 0xff;
    buf[2] = (len >> 8) & 0xff;
    buf[3] = len & 0xff;
    buf[4] = id;
    buf.setRange(5, 5 + p.length, p);
    return buf;
  }
}

/// 一个 Peer 的 TCP 连接管理
class PeerConnection {
  final String host;
  final int port;
  final Uint8List infoHash;
  final Uint8List peerId;
  final bool clientMode; // true = 我们是主动连接方

  Socket? _socket;
  final List<int> _recvBuf = [];
  bool _closed = false;
  bool _handshakeDone = false;
  bool _choked = true;
  bool _interested = false;
  bool _peerChoked = true;
  bool _peerInterested = false;

  /// 消息回调（handshake 完成后开始投递）
  final Stream<PeerWireMessage> _msgStream = StreamController<PeerWireMessage>.broadcast().stream;
  Stream<PeerWireMessage> get messages => _msgStream;
  final _msgController = StreamController<PeerWireMessage>.broadcast();

  /// peer 报告的扩展协议位（BEP-10）
  int get extensionBits {
    if (_peerReserved.length < 6) return 0;
    return _peerReserved[5];
  }

  Uint8List _peerReserved = Uint8List(8);
  Uint8List? _peerId;

  PeerConnection({
    required this.host,
    required this.port,
    required this.infoHash,
    required this.peerId,
    this.clientMode = true,
  });

  Stream<PeerWireMessage> get _out => _msgController.stream;
  Stream<PeerWireMessage> get incoming => _msgController.stream;

  bool get isClosed => _closed;
  bool get isHandshakeDone => _handshakeDone;
  bool get amChoked => _choked;
  bool get amInterested => _interested;
  bool get peerChoked => _peerChoked;
  bool get peerInterested => _peerInterested;

  Future<void> connect({Duration timeout = const Duration(seconds: 15)}) async {
    if (!clientMode) {
      throw StateError('Server mode connect() not implemented in this scope');
    }
    _socket = await Socket.connect(host, port, timeout: timeout);
    _socket!.listen(_onData, onError: _onError, onDone: _onDone);
    final hs = PeerHandshake(infoHash: infoHash, peerId: peerId);
    hs.enableExtension();
    _socket!.add(hs.encode());
    await _socket!.flush();
  }

  /// 写入一个 peer 消息
  void send(PeerWireMessage msg) {
    _socket?.add(msg.encode());
  }

  void sendInterested() {
    _interested = true;
    send(PeerWireMessage(PeerMessage.interested));
  }

  void sendNotInterested() {
    _interested = false;
    send(PeerWireMessage(PeerMessage.notInterested));
  }

  void sendRequest(int pieceIndex, int offset, int length) {
    final payload = Uint8List(12);
    final bd = payload.buffer.asByteData();
    bd.setUint32(0, pieceIndex);
    bd.setUint32(4, offset);
    bd.setUint32(8, length);
    send(PeerWireMessage(PeerMessage.request, payload));
  }

  void sendHave(int pieceIndex) {
    final payload = Uint8List(4);
    payload.buffer.asByteData().setUint32(0, pieceIndex);
    send(PeerWireMessage(PeerMessage.have, payload));
  }

  void sendBitfield(Uint8List bits) {
    send(PeerWireMessage(PeerMessage.bitfield, bits));
  }

  void close() {
    if (_closed) return;
    _closed = true;
    try {
      _socket?.destroy();
    } catch (_) {}
    _msgController.close();
  }

  // ----- 接收处理 -----

  void _onData(List<int> data) {
    _recvBuf.addAll(data);
    _tryParse();
  }

  void _tryParse() {
    // 解析 handshake
    if (!_handshakeDone) {
      if (_recvBuf.length < PeerHandshake.handshakeLength) return;
      final handshakeBytes = Uint8List.fromList(_recvBuf.sublist(0, 68));
      final hs = PeerHandshake.tryDecode(handshakeBytes);
      if (hs == null) {
        close();
        return;
      }
      _peerReserved = hs.reserved;
      _peerId = hs.peerId;
      _recvBuf.removeRange(0, 68);
      _handshakeDone = true;
      _msgController.add(PeerWireMessage(PeerMessage.keepAlive)); // 标记 handshake 完成
      // 用 keep-alive 作为信号 - 实际项目应有专用事件
      _msgController.add(PeerWireMessage(0xfe, Uint8List.fromList([0]))); // 假信号
      return;
    }

    // 解析常规消息
    while (_recvBuf.length >= 4) {
      final len = (_recvBuf[0] << 24) |
          (_recvBuf[1] << 16) |
          (_recvBuf[2] << 8) |
          _recvBuf[3];
      if (len == 0) {
        // keep-alive
        _msgController.add(PeerWireMessage(PeerMessage.keepAlive));
        _recvBuf.removeRange(0, 4);
        continue;
      }
      if (_recvBuf.length < 4 + len) return;
      final id = _recvBuf[4];
      final payload = Uint8List.fromList(_recvBuf.sublist(5, 4 + len));
      _handleMessage(id, payload);
      _msgController.add(PeerWireMessage(id, payload));
      _recvBuf.removeRange(0, 4 + len);
    }
  }

  void _handleMessage(int id, Uint8List payload) {
    switch (id) {
      case PeerMessage.choke:
        _choked = true;
        break;
      case PeerMessage.unchoke:
        _choked = false;
        break;
      case PeerMessage.interested:
        _peerInterested = true;
        break;
      case PeerMessage.notInterested:
        _peerInterested = false;
        break;
      default:
        break;
    }
  }

  void _onError(Object e) {
    if (!_closed) _msgController.addError(e);
    close();
  }

  void _onDone() {
    close();
  }
}
