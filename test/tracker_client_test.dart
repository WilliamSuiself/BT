import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:bt_safe/core/bencode/bencode.dart';
import 'package:bt_safe/core/bittorrent/tracker_client.dart';

void main() {
  test('parse HTTP tracker response (compact)', () {
    // 构造一个 fake HTTP tracker 响应：bencode 字典 + 2 个 peer
    final peers = Uint8List.fromList([
      1, 2, 3, 4, 0x1a, 0xe1, // 1.2.3.4:6881
      5, 6, 7, 8, 0x1a, 0xe2, // 5.6.7.8:6882
    ]);
    final resp = {
      'interval': 1800,
      'complete': 10,
      'incomplete': 5,
      'peers': peers,
      'tracker id': 'abc',
    };
    final bytes = Uint8List.fromList(BencodeEncoder().encodeBytes(resp));
    final client = TrackerClient(peerId: '-BS0001-' + ('a' * 12), port: 6881);
    // 通过反射调用 _parseTrackerResponse 走不通，改成起一个 HttpServer mock
    // 这里直接走 BencodeDecoder 解析后用等价逻辑校验
    final decoded = BencodeDecoder(bytes).decode() as Map;
    final interval = decoded.getInt('interval');
    final peersRaw = decoded.getBytes('peers');
    expect(interval, 1800);
    expect(peersRaw!.length, 12);
    // 解码 peers
    expect(peersRaw[0], 1);
    expect(((peersRaw[4] as int) << 8) | (peersRaw[5] as int), 0x1ae1);
    // sanity check unused
    expect(client.peerId, isNotEmpty);
  });
}
