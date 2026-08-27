import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:bt_safe/core/bittorrent/torrent_parser.dart';
import 'package:bt_safe/core/bencode/bencode.dart';
import 'package:crypto/crypto.dart';

void main() {
  test('parser handles single-file torrent', () {
    // 构造一个最简单文件种子：单文件 32 字节，piece 16 字节
    // pieces 字段放 2 个 SHA1 占位
    final fakePieces = Uint8List.fromList(List.filled(40, 0xaa));
    final info = {
      'name': Uint8List.fromList(utf8('test.bin')),
      'piece length': 16,
      'pieces': fakePieces,
      'length': 32,
    };
    final top = {
      'announce': Uint8List.fromList(utf8('udp://t')),
      'info': info,
    };
    final bytes = Uint8List.fromList(BencodeEncoder().encodeBytes(top));
    final t = TorrentParser.parse(bytes);
    expect(t.name, 'test.bin');
    expect(t.pieceLength, 16);
    expect(t.pieceCount, 2);
    expect(t.totalLength, 32);
    expect(t.trackers.announce, ['udp://t']);
    // infoHash 与独立 SHA1 一致
    final infoBytes = BencodeEncoder().encodeBytes(info);
    final expectHash = sha1.convert(infoBytes).bytes;
    expect(t.infoHash, Uint8List.fromList(expectHash));
  });
}

List<int> utf8(String s) => s.codeUnits;
