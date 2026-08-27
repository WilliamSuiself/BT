import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:bt_safe/core/bittorrent/peer_protocol.dart';

void main() {
  group('PeerWire', () {
    test('handshake round trip', () {
      final infoHash = Uint8List.fromList(List.generate(20, (i) => i));
      final peerId = Uint8List.fromList(List.generate(20, (i) => i + 100));
      final hs = PeerHandshake(infoHash: infoHash, peerId: peerId);
      hs.enableExtension();
      final bytes = hs.encode();
      expect(bytes.length, 68);
      expect(bytes[0], 19);
      final decoded = PeerHandshake.tryDecode(bytes);
      expect(decoded, isNotNull);
      expect(decoded!.infoHash, infoHash);
      expect(decoded.peerId, peerId);
      expect(decoded.reserved[5] & 0x10, 0x10);
    });

    test('message encode/decode', () {
      final msg = PeerWireMessage(PeerMessage.have, Uint8List(4)..buffer.asByteData().setUint32(0, 42));
      final bytes = msg.encode();
      // len=5, id=4, payload=4
      expect(bytes.length, 9);
      expect(bytes[4], 4);
      final pl = bytes.sublist(5, 9);
      expect(pl.buffer.asByteData().getUint32(0), 42);
    });

    test('keep-alive encode', () {
      final msg = PeerWireMessage(PeerMessage.keepAlive);
      final bytes = msg.encode();
      expect(bytes.length, 4);
      expect(bytes.every((b) => b == 0), true);
    });
  });
}
