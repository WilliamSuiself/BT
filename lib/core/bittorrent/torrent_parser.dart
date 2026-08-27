/// .torrent 解析器
library torrent_parser;

import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import '../../models/torrent_info.dart';
import '../bencode/bencode.dart';

class TorrentParseException implements Exception {
  final String message;
  TorrentParseException(this.message);
  @override
  String toString() => 'TorrentParseException: $message';
}

class TorrentParser {
  /// 解析 .torrent 文件字节流
  ///
  /// 关键点：info 字典必须独立做一次 SHA1，得到 infoHash。
  /// 实现思路：先定位 info 字典在原文中的字节范围，
  /// 再对该范围单独 SHA1（而不是对重新编码后的字典）。
  static TorrentInfo parse(Uint8List torrentBytes) {
    final decoded = BencodeDecoder(torrentBytes).decode();
    if (decoded is! Map) {
      throw TorrentParseException('种子顶层必须是字典');
    }

    // 找 info 字典的范围（关键：正确计算 infoHash）
    final infoRange = _findInfoDictRange(torrentBytes);
    if (infoRange == null) {
      throw TorrentParseException('找不到 info 字典');
    }
    final infoHash = Uint8List.fromList(
        sha1.convert(torrentBytes.sublist(infoRange.$1, infoRange.$2)).bytes);

    final info = decoded.getDict('info');
    if (info == null) {
      throw TorrentParseException('缺少 info 字典');
    }

    // name
    final name = info.getUtf8('name');

    // piece length
    final pieceLength = info.getInt('piece length') ?? 0;
    if (pieceLength <= 0) {
      throw TorrentParseException('piece length 非法: $pieceLength');
    }

    // pieces
    final piecesRaw = info.getBytes('pieces');
    if (piecesRaw == null) {
      throw TorrentParseException('缺少 pieces');
    }
    if (piecesRaw.length % 20 != 0) {
      throw TorrentParseException('pieces 长度不是 20 的倍数');
    }

    // 文件列表：单文件模式或多文件模式
    final files = <TorrentFile>[];
    int totalLength = 0;

    if (info.getDict('files') != null) {
      // 多文件
      final list = info.getList('files')!;
      for (final f in list) {
        if (f is! Map) continue;
        final length = (f.getInt('length') ?? 0);
        final pathList = f.getList('path') ?? const [];
        final pathParts = pathList
            .whereType<Uint8List>()
            .map((b) => utf8.decode(b, allowMalformed: true))
            .toList();
        final rel = pathParts.join('/');
        files.add(TorrentFile(
          path: rel.isEmpty ? name ?? 'file' : rel,
          length: length,
          offsetInTorrent: totalLength,
        ));
        totalLength += length;
      }
    } else {
      // 单文件
      final length = info.getInt('length') ?? 0;
      files.add(TorrentFile(
        path: name ?? 'file',
        length: length,
        offsetInTorrent: 0,
      ));
      totalLength = length;
    }

    // trackers
    final announceList = <List<String>>[];
    final announce = <String>[];
    final main = decoded.getBytes('announce');
    if (main != null) {
      final s = utf8.decode(main, allowMalformed: true);
      announce.add(s);
      announceList.add([s]);
    }
    final alt = decoded.getList('announce-list');
    if (alt != null) {
      for (final tier in alt) {
        if (tier is List) {
          final t = tier
              .whereType<Uint8List>()
              .map((b) => utf8.decode(b, allowMalformed: true))
              .toList();
          if (t.isNotEmpty) announceList.add(t);
        }
      }
    }

    final trackers = TrackerInfo(announce: announce, announceList: announceList);

    return TorrentInfo(
      infoHash: infoHash,
      name: name,
      pieceLength: pieceLength,
      pieces: piecesRaw,
      files: files,
      totalLength: totalLength,
      trackers: trackers,
      creationDate: decoded.getInt('creation date'),
      comment: decoded.getUtf8('comment'),
      createdBy: decoded.getUtf8('created by'),
      isPrivate: (info.getInt('private') ?? 0) != 0,
    );
  }

  /// 在原文里找到 info 字典的字节范围 [start, end)
  ///
  /// 策略：扫描 "4:info"（d...4:info...e），递归平衡花括号定位匹配的字典结束。
  static (int start, int end)? _findInfoDictRange(Uint8List bytes) {
    final sig = Uint8List.fromList(utf8.encode('4:info'));
    int pos = -1;
    for (var i = 0; i + sig.length <= bytes.length; i++) {
      var match = true;
      for (var j = 0; j < sig.length; j++) {
        if (bytes[i + j] != sig[j]) {
          match = false;
          break;
        }
      }
      if (match) {
        pos = i;
        break;
      }
    }
    if (pos < 0) return null;

    // "4:info" 后是 "d...e" 的 dict，从 pos + sig.length 起应该是 'd'
    int dictStart = -1;
    for (var i = pos + sig.length; i < bytes.length; i++) {
      if (bytes[i] == 0x64 /* d */) {
        dictStart = i;
        break;
      }
      // 跳过空格/换行（健壮性）
    }
    if (dictStart < 0) return null;

    // 从 dictStart 开始匹配嵌套
    int depth = 0;
    int i2 = dictStart;
    while (i2 < bytes.length) {
      final c = bytes[i2];
      if (c == 0x64 /* d */ || c == 0x6c /* l */) {
        depth++;
      } else if (c == 0x65 /* e */) {
        depth--;
        if (depth == 0) {
          return (dictStart, i2 + 1);
        }
      } else if (c >= 0x30 && c <= 0x39 /* 0-9 */) {
        // 字节串，跳过
        final colon = _indexOf(bytes, 0x3a, i2 + 1);
        if (colon < 0) return null;
        final len = int.parse(utf8.decode(bytes.sublist(i2, colon)));
        i2 = colon + 1 + len;
        continue;
      } else if (c == 0x69 /* i */) {
        final end = _indexOf(bytes, 0x65 /* e */, i2 + 1);
        if (end < 0) return null;
        i2 = end + 1;
        continue;
      }
      i2++;
    }
    return null;
  }

  static int _indexOf(Uint8List bytes, int target, int start) {
    for (var i = start; i < bytes.length; i++) {
      if (bytes[i] == target) return i;
    }
    return -1;
  }
}
