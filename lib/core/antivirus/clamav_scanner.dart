/// ClamAV 病毒扫描客户端
///
/// 通过 clamd UNIX socket 或 TCP socket，使用 INSTREAM 协议扫描本地文件。
/// INSTREAM 协议：
///   客户端 -> 服务端：zINSTREAM\0<length:4 BE><data:length>...<0:4>（终止）
///   服务端 -> 客户端：stream: <result>\n
library clamav_scanner;

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

class ScanResult {
  final String status; // 'OK' | 'FOUND' | 'ERROR'
  final String? signature; // 病毒名
  final String raw;
  const ScanResult({required this.status, this.signature, required this.raw});
}

class ClamdScanner {
  final String host;
  final int port;
  final Duration timeout;
  Socket? _socket;

  ClamdScanner({this.host = '127.0.0.1', this.port = 3310, this.timeout = const Duration(seconds: 60)});

  /// 单文件扫描
  Future<ScanResult> scanFile(String filePath) async {
    final file = File(filePath);
    if (!file.existsSync()) {
      return const ScanResult(status: 'ERROR', raw: 'file not found');
    }
    final raf = await file.open();
    try {
      _socket ??= await Socket.connect(host, port, timeout: timeout);
      _socket!.add(utf8Bytes('zINSTREAM\0'));
      // 分块发送，最大 1MB/chunk（BETTER 推荐，但 clamd 接受任意 <= stream 缓冲）
      const chunkSize = 64 * 1024;
      final buffer = Uint8List(chunkSize);
      while (true) {
        final read = await raf.readInto(buffer, 0, chunkSize);
        if (read == 0) break;
        _writeUint32(_socket!, read);
        _socket!.add(Uint8List.sublistView(buffer, 0, read));
        await _socket!.flush();
      }
      // 终止
      _writeUint32(_socket!, 0);
      await _socket!.flush();

      // 读响应
      final line = await _readLine();
      return _parse(line);
    } finally {
      await raf.close();
    }
  }

  /// 关闭连接
  Future<void> close() async {
    await _socket?.flush();
    _socket?.destroy();
    _socket = null;
  }

  Future<String> _readLine() async {
    final completer = Completer<String>();
    final buf = <int>[];
    final sub = _socket!.listen((data) {
      for (final b in data) {
        if (b == 0x0a) {
          if (!completer.isCompleted) {
            completer.complete(String.fromCharCodes(buf));
          }
          return;
        }
        buf.add(b);
      }
    }, onError: (e) {
      if (!completer.isCompleted) completer.completeError(e);
    });
    final result = await completer.future.timeout(timeout);
    await sub.cancel();
    return result;
  }

  ScanResult _parse(String line) {
    // 格式：stream: OK 或 stream: <name> FOUND 或 stream: <name> ERROR
    if (!line.startsWith('stream:')) {
      return ScanResult(status: 'ERROR', raw: line);
    }
    final body = line.substring('stream:'.length).trim();
    if (body == 'OK') {
      return const ScanResult(status: 'OK', raw: 'OK');
    }
    final parts = body.split(' ');
    if (parts.length >= 2 && parts.last == 'FOUND') {
      return ScanResult(status: 'FOUND', signature: parts.first, raw: body);
    }
    return ScanResult(status: 'ERROR', raw: body);
  }

  static void _writeUint32(Socket s, int v) {
    final b = Uint8List(4);
    b.buffer.asByteData().setUint32(0, v);
    s.add(b);
  }

  static List<int> utf8Bytes(String s) => s.codeUnits;
}
