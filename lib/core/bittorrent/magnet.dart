/// Magnet 链接解析
///
/// 格式：
///   magnet:?xt=urn:btih:<40 位 hex 或 32 位 base32>&dn=<name>&tr=<tracker>&...
///
/// 我们只关心 xt（必有）、dn（可选）、tr（可多个）、x.pe（可选，peer 来源）
library magnet;

import 'dart:convert';
import 'dart:typed_data';

class MagnetInfo {
  final Uint8List infoHash; // 20 字节
  final String? displayName;
  final List<String> trackers;
  final List<String> exactSources; // x.pe，可选 peer 来源

  const MagnetInfo({
    required this.infoHash,
    this.displayName,
    required this.trackers,
    required this.exactSources,
  });

  /// BEP-9 哈希展示
  String get hex => infoHash
      .map((b) => b.toRadixString(16).padLeft(2, '0'))
      .join();
}

class MagnetParser {
  static MagnetInfo? tryParse(String uri) {
    if (!uri.startsWith('magnet:?')) return null;
    final query = uri.substring('magnet:?'.length);
    final parts = query.split('&');

    Uint8List? infoHash;
    String? dn;
    final trs = <String>[];
    final xpe = <String>[];

    for (final raw in parts) {
      if (raw.isEmpty) continue;
      final eq = raw.indexOf('=');
      final key = eq < 0 ? raw : raw.substring(0, eq);
      final val = eq < 0 ? '' : raw.substring(eq + 1);
      switch (key) {
        case 'xt':
          // urn:btih:<hash>
          if (val.startsWith('urn:btih:')) {
            final hashPart = val.substring('urn:btih:'.length);
            infoHash = _decodeHash(hashPart);
          } else if (val.startsWith('urn:btmh:')) {
            // BEP-52 多哈希，本工具暂不支持 v2 但不抛错
            infoHash = null;
          }
          break;
        case 'dn':
          dn = Uri.decodeComponent(val);
          break;
        case 'tr':
          trs.add(Uri.decodeComponent(val));
          break;
        case 'x.pe':
          xpe.add(Uri.decodeComponent(val));
          break;
      }
    }

    if (infoHash == null) return null;
    return MagnetInfo(
      infoHash: infoHash,
      displayName: dn,
      trackers: trs,
      exactSources: xpe,
    );
  }

  /// 支持 40 位 hex / 32 位 base32 两种编码
  static Uint8List? _decodeHash(String s) {
    if (s.length == 40) {
      try {
        final out = Uint8List(20);
        for (var i = 0; i < 20; i++) {
          out[i] = int.parse(s.substring(i * 2, i * 2 + 2), radix: 16);
        }
        return out;
      } catch (_) {
        return null;
      }
    } else if (s.length == 32) {
      try {
        return _base32Decode(s.toUpperCase());
      } catch (_) {
        return null;
      }
    }
    return null;
  }

  static Uint8List _base32Decode(String input) {
    const alphabet = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ234567';
    final out = <int>[];
    int buffer = 0;
    int bitsLeft = 0;
    for (final ch in input.codeUnits) {
      final idx = alphabet.indexOf(String.fromCharCode(ch));
      if (idx < 0) throw const FormatException('base32 非法字符');
      buffer = (buffer << 5) | idx;
      bitsLeft += 5;
      if (bitsLeft >= 8) {
        bitsLeft -= 8;
        out.add((buffer >> bitsLeft) & 0xff);
      }
    }
    return Uint8List.fromList(out);
  }

  /// 反向：构造磁力链（hex 编码）
  static String buildMagnet(Uint8List infoHash, {String? name, List<String> trackers = const []}) {
    final hex = infoHash
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join();
    final buf = StringBuffer('magnet:?xt=urn:btih:$hex');
    if (name != null && name.isNotEmpty) {
      buf.write('&dn=${Uri.encodeComponent(name)}');
    }
    for (final tr in trackers) {
      buf.write('&tr=${Uri.encodeComponent(tr)}');
    }
    return buf.toString();
  }
}
