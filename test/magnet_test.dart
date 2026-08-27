import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:bt_safe/core/bittorrent/magnet.dart';

void main() {
  group('Magnet', () {
    test('parse hex hash', () {
      final m = MagnetParser.tryParse(
          'magnet:?xt=urn:btih:1234567890abcdef1234567890abcdef12345678&dn=hello&tr=udp%3A%2F%2Ftracker.openbittorrent.com%3A80');
      expect(m, isNotNull);
      expect(m!.infoHash.length, 20);
      expect(m.displayName, 'hello');
      expect(m.trackers, ['udp://tracker.openbittorrent.com:80']);
    });

    test('roundtrip', () {
      final hash = Uint8List.fromList(List.generate(20, (i) => i));
      final s = MagnetParser.buildMagnet(hash, name: 'x', trackers: ['udp://t']);
      final back = MagnetParser.tryParse(s)!;
      expect(back.infoHash, hash);
      expect(back.displayName, 'x');
      expect(back.trackers, ['udp://t']);
    });

    test('parse base32 hash', () {
      // 40 hex 字节的 32 字符 base32 等价
      const hex40 = '1234567890abcdef1234567890abcdef12345678';
      final hex = MagnetParser.tryParse('magnet:?xt=urn:btih:$hex40')!;
      // base32 版本长度 32
      final base32Hash = _hexToBase32(hex40);
      final b32 = MagnetParser.tryParse('magnet:?xt=urn:btih:$base32Hash')!;
      expect(hex.infoHash, b32.infoHash);
    });
  });
}

String _hexToBase32(String hex) {
  // 仅供测试，简化版
  const alphabet = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ234567';
  final bytes = <int>[];
  for (var i = 0; i < hex.length; i += 2) {
    bytes.add(int.parse(hex.substring(i, i + 2), radix: 16));
  }
  int buffer = 0;
  int bitsLeft = 0;
  final out = StringBuffer();
  for (final b in bytes) {
    buffer = (buffer << 8) | b;
    bitsLeft += 8;
    while (bitsLeft >= 5) {
      bitsLeft -= 5;
      out.write(alphabet[(buffer >> bitsLeft) & 0x1f]);
    }
  }
  return out.toString();
}
