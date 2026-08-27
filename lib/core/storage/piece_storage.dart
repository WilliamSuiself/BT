/// Piece 存储：负责将 piece/block 数据写入磁盘 + SHA1 校验 + 断点续传
///
/// 设计：
/// - 单文件 torrent：所有 piece 按 pieceLength 顺序写入一个文件（最后一个 piece 可能更短）
/// - 多文件 torrent：所有文件按 TorrentFile 顺序拼接成一个逻辑字节流，
///   再按 piece 切分；写入时按 TorrentFile.offsetInTorrent 路由到对应文件
/// - 每个 piece 完成时 SHA1 校验；通过后写一个 `.piece-<index>` 标记文件
/// - 启动时扫描这些标记决定是否需要重新下载（断点续传）
library piece_storage;

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../models/torrent_info.dart';

/// 状态
enum PieceState { missing, downloading, verified }

class PieceMeta {
  final int index;
  final int length;
  final int offsetInTorrent; // piece 在拼接流中的字节偏移
  final Uint8List expectedHash;
  PieceState state;

  PieceMeta({
    required this.index,
    required this.length,
    required this.offsetInTorrent,
    required this.expectedHash,
    this.state = PieceState.missing,
  });
}

class PieceStorage {
  final TorrentInfo torrent;
  final Directory saveDir; // 种子下载根目录（包含所有文件）
  final List<PieceMeta> pieces;
  final List<RandomAccessFile> _openFiles = [];

  PieceStorage({required this.torrent, required this.saveDir}) : pieces = [] {
    _init();
  }

  void _init() {
    var offset = 0;
    final pieceCount = torrent.pieceCount;
    for (var i = 0; i < pieceCount; i++) {
      final isLast = i == pieceCount - 1;
      final len = isLast
          ? torrent.totalLength - i * torrent.pieceLength
          : torrent.pieceLength;
      pieces.add(PieceMeta(
        index: i,
        length: len,
        offsetInTorrent: offset,
        expectedHash: torrent.pieceHash(i),
      ));
      offset += len;
    }
    if (!saveDir.existsSync()) {
      saveDir.createSync(recursive: true);
    }
  }

  /// 扫描磁盘上的 `.verified-<index>` 标记，恢复已完成的 piece
  Future<void> loadResumeState() async {
    for (final piece in pieces) {
      final marker = File(p.join(saveDir.path, '.verified-${piece.index}'));
      if (await marker.exists()) {
        piece.state = PieceState.verified;
      }
    }
  }

  /// 写入一段 block（piece 的某一段）
  ///
  /// [pieceIndex] 第几个 piece
  /// [blockOffset] 在该 piece 内的偏移
  /// [data] 实际字节
  Future<void> writeBlock(int pieceIndex, int blockOffset, Uint8List data) async {
    final piece = pieces[pieceIndex];
    final torrentOffset = piece.offsetInTorrent + blockOffset;
    await _writeAt(torrentOffset, data);
  }

  /// 读取完整 piece（用于 SHA1 校验）
  Future<Uint8List> readPiece(int pieceIndex) async {
    final piece = pieces[pieceIndex];
    final buf = Uint8List(piece.length);
    await _readAt(piece.offsetInTorrent, buf);
    return buf;
  }

  /// 校验 piece；通过则写 `.verified-<index>` 标记
  Future<bool> verifyPiece(int pieceIndex) async {
    final piece = pieces[pieceIndex];
    final data = await readPiece(pieceIndex);
    final digest = sha1.convert(data).bytes;
    final expected = piece.expectedHash;
    if (!_bytesEqual(digest, expected)) {
      return false;
    }
    // 写标记
    final marker = File(p.join(saveDir.path, '.verified-${pieceIndex}'));
    await marker.writeAsString('1', flush: true);
    piece.state = PieceState.verified;
    return true;
  }

  /// 全部 piece 验证完成？
  bool get isComplete => pieces.every((p) => p.state == PieceState.verified);

  /// 已完成的字节数（基于 piece 维度，piece 内部分 block 缺失则记 0）
  int get completedBytes => pieces
      .where((p) => p.state == PieceState.verified)
      .fold<int>(0, (acc, p) => acc + p.length);

  /// 进度 0..1
  double get progress =>
      torrent.totalLength == 0 ? 0 : completedBytes / torrent.totalLength;

  Future<void> _writeAt(int torrentOffset, Uint8List data) async {
    var remaining = data;
    var pos = torrentOffset;
    var dataOffset = 0;
    while (remaining.isNotEmpty) {
      final file = _findFileForOffset(pos);
      if (file == null) {
        throw StateError('offset $pos 超出 torrent 范围');
      }
      final localOffset = pos - file.offset;
      final canWrite = (file.length - localOffset).clamp(0, remaining.length);
      if (canWrite <= 0) {
        pos += 1; // 防御性跳过（实际不应发生）
        continue;
      }
      final raf = await _openFile(file.path);
      await raf.setPosition(localOffset);
      await raf.writeFrom(remaining.sublist(dataOffset, dataOffset + canWrite));
      pos += canWrite;
      dataOffset += canWrite;
      remaining = remaining.sublist(canWrite);
    }
  }

  Future<void> _readAt(int torrentOffset, Uint8List buf) async {
    var remaining = buf.length;
    var pos = torrentOffset;
    var bufOffset = 0;
    while (remaining > 0) {
      final file = _findFileForOffset(pos);
      if (file == null) {
        throw StateError('offset $pos 超出 torrent 范围');
      }
      final localOffset = pos - file.offset;
      final canRead = (file.length - localOffset).clamp(0, remaining);
      if (canRead <= 0) {
        pos += 1;
        continue;
      }
      final raf = await _openFile(file.path);
      await raf.setPosition(localOffset);
      final tmp = Uint8List(canRead);
      final read = await raf.readInto(tmp, 0, canRead);
      buf.setRange(bufOffset, bufOffset + read, tmp.sublist(0, read));
      pos += read;
      bufOffset += read;
      remaining -= read;
    }
  }

  /// 给定 torrent 拼接偏移，找对应文件
  _FileRange? _findFileForOffset(int offset) {
    for (final f in torrent.files) {
      final start = f.offsetInTorrent ?? 0;
      final end = start + f.length;
      if (offset >= start && offset < end) {
        return _FileRange(
          path: p.join(saveDir.path, f.path),
          offset: start,
          length: f.length,
        );
      }
    }
    return null;
  }

  Future<RandomAccessFile> _openFile(String path) async {
    final f = File(path);
    if (!await f.exists()) {
      await f.create(recursive: true);
      // 把文件长度截到合适大小
      final raf = await f.open(mode: FileMode.append);
      await raf.close();
    }
    final raf = await f.open(mode: FileMode.append);
    _openFiles.add(raf);
    return raf;
  }

  Future<void> close() async {
    for (final raf in _openFiles) {
      try {
        await raf.close();
      } catch (_) {}
    }
    _openFiles.clear();
  }

  static bool _bytesEqual(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}

class _FileRange {
  final String path;
  final int offset; // torrent 内偏移
  final int length;
  _FileRange({required this.path, required this.offset, required this.length});
}

/// 工具：获取应用下载根目录
Future<Directory> defaultDownloadRoot() async {
  final base = await getApplicationDocumentsDirectory();
  final dir = Directory(p.join(base.path, 'downloads'));
  if (!await dir.exists()) {
    await dir.create(recursive: true);
  }
  return dir;
}
