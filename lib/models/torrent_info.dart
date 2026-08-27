/// Torrent 元数据模型
library torrent_info;

import 'dart:typed_data';

/// 单个文件信息
class TorrentFile {
  final String path; // 相对种子根目录的路径
  final int length; // 字节数
  final int? offsetInTorrent; // 在所有文件拼接后的偏移（BEP-47 用到）

  const TorrentFile({
    required this.path,
    required this.length,
    this.offsetInTorrent,
  });
}

/// Tracker URL 列表
class TrackerInfo {
  final List<String> announce; // 主 tracker
  final List<List<String>> announceList; // 多 tracker 层级（BEP-12）

  const TrackerInfo({required this.announce, required this.announceList});
}

/// 完整 .torrent 文件解析结果
class TorrentInfo {
  final Uint8List infoHash; // 20 字节 SHA1，对应磁力链 xt=urn:btih:
  final String? name; // 顶层名称
  final int pieceLength; // 单个 piece 字节数
  final Uint8List pieces; // 拼接的所有 piece 哈希（每 20 字节一个 SHA1）
  final List<TorrentFile> files; // 单文件/多文件列表
  final int totalLength;
  final TrackerInfo trackers;
  final int? creationDate;
  final String? comment;
  final String? createdBy;
  final bool isPrivate;

  TorrentInfo({
    required this.infoHash,
    required this.name,
    required this.pieceLength,
    required this.pieces,
    required this.files,
    required this.totalLength,
    required this.trackers,
    this.creationDate,
    this.comment,
    this.createdBy,
    this.isPrivate = false,
  });

  /// piece 数量
  int get pieceCount {
    final p = pieceLength == 0 ? 0 : (totalLength + pieceLength - 1) ~/ pieceLength;
    return p;
  }

  /// 取第 i 个 piece 的 SHA1
  Uint8List pieceHash(int index) {
    final start = index * 20;
    return Uint8List.sublistView(pieces, start, start + 20);
  }
}
