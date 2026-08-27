import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:bt_safe/core/bencode/bencode.dart';

void main() {
  group('Bencode', () {
    test('decode integer', () {
      final bytes = Uint8List.fromList('i42e'.codeUnits);
      expect(BencodeDecoder(bytes).decode(), 42);
    });

    test('decode bytes', () {
      final bytes = Uint8List.fromList('4:spam'.codeUnits);
      final r = BencodeDecoder(bytes).decode();
      expect(r, isA<Uint8List>());
      expect(String.fromCharCodes(r as Uint8List), 'spam');
    });

    test('decode list', () {
      final bytes = Uint8List.fromList('l4:spam4:eggse'.codeUnits);
      final r = BencodeDecoder(bytes).decode() as List;
      expect(r.length, 2);
      expect(String.fromCharCodes(r[0] as Uint8List), 'spam');
      expect(String.fromCharCodes(r[1] as Uint8List), 'eggs');
    });

    test('decode dict', () {
      final bytes = Uint8List.fromList('d3:cow3:moo4:spam4:eggse'.codeUnits);
      final r = BencodeDecoder(bytes).decode() as Map;
      // key 现在是 String
      expect(String.fromCharCodes(r['cow'] as Uint8List), 'moo');
      expect(String.fromCharCodes(r['spam'] as Uint8List), 'eggs');
    });

    test('encode int', () {
      expect(BencodeEncoder().encode(42), 'i42e');
    });

    test('round trip dict sorted', () {
      // 注意 key 应排序
      final src = <String, Object?>{
        'b': 2,
        'a': 1,
      };
      final s = BencodeEncoder().encode(src);
      expect(s.startsWith('d'), true);
      expect(s.indexOf('1:a'), lessThan(s.indexOf('1:b')));
    });
  });
}
