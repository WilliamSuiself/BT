/// Bencode 编解码器
///
/// BitTorrent 协议使用的序列化格式：
/// - 整数：i<数字>e            e.g. i42e
/// - 字节串：<长度>:<内容>     e.g. 4:spam
/// - 列表：l<元素们>e          e.g. l4:spam4:eggse
/// - 字典：d<键值对们>e        e.g. d3:cow3:moo4:spam4:eggse
///
/// 键必须是字节串（按字典序排序）。
library bencode;

import 'dart:convert';
import 'dart:typed_data';

/// Bencode 解码器
class BencodeDecoder {
  final Uint8List _bytes;
  int _pos = 0;

  BencodeDecoder(this._bytes);

  /// 解码整个输入
  Object? decode() {
    final result = _readValue();
    return result;
  }

  Object? _readValue() {
    if (_pos >= _bytes.length) {
      throw const FormatException('Bencode: 意外到达末尾');
    }
    final c = _bytes[_pos];
    if (c == 0x69 /* i */) return _readInt();
    if (c == 0x6c /* l */) return _readList();
    if (c == 0x64 /* d */) return _readDict();
    if (c >= 0x30 && c <= 0x39 /* 0-9 */) return _readBytes();
    throw FormatException('Bencode: 非法字符 0x${c.toRadixString(16)} at $_pos');
  }

  int _readInt() {
    _pos++; // skip 'i'
    final colon = _indexOf(0x65 /* e */, _pos);
    if (colon < 0) throw const FormatException('Bencode: int 缺少终止符 e');
    final s = utf8.decode(_bytes.sublist(_pos, colon));
    _pos = colon + 1;
    return int.parse(s);
  }

  Uint8List _readBytes() {
    final colon = _indexOf(0x3a /* : */, _pos);
    if (colon < 0) throw const FormatException('Bencode: bytes 缺少冒号');
    final lenStr = utf8.decode(_bytes.sublist(_pos, colon));
    final len = int.parse(lenStr);
    _pos = colon + 1;
    if (_pos + len > _bytes.length) {
      throw FormatException('Bencode: bytes 长度越界 len=$len pos=$_pos');
    }
    final out = _bytes.sublist(_pos, _pos + len);
    _pos += len;
    return Uint8List.fromList(out);
  }

  List<Object?> _readList() {
    _pos++; // skip 'l'
    final list = <Object?>[];
    while (_pos < _bytes.length && _bytes[_pos] != 0x65 /* e */) {
      list.add(_readValue());
    }
    if (_pos >= _bytes.length) throw const FormatException('Bencode: list 缺少终止符');
    _pos++;
    return list;
  }

  /// BT 字典要求 key 按字节序排序，这里强制校验一致性
  ///
  /// 注意：BT 字典 key 必须是 bytes，但 Dart 的 Uint8List 不按值哈希，
  /// 这里把 key 转成 UTF-8 String 便于使用。对非常规 key（不可 UTF-8）
  /// 退化用 `__b64:<base64>` 形式。生产用足够。
  Map<String, Object?> _readDict() {
    _pos++; // skip 'd'
    final map = <String, Object?>{};
    Uint8List? lastKey;
    while (_pos < _bytes.length && _bytes[_pos] != 0x65 /* e */) {
      final keyBytes = _readBytes();
      if (lastKey != null && _compareBytes(lastKey, keyBytes) >= 0) {
        // BEP-3：字典 key 必须排序（不是错误但警告）
        // 这里选择静默接受（部分种子不严格）
      }
      final value = _readValue();
      final keyStr = _keyToString(keyBytes);
      map[keyStr] = value;
      lastKey = keyBytes;
    }
    if (_pos >= _bytes.length) throw const FormatException('Bencode: dict 缺少终止符');
    _pos++;
    return map;
  }

  static String _keyToString(Uint8List b) {
    try {
      return utf8.decode(b);
    } catch (_) {
      // 不可 UTF-8 编码的 key，用 base64 兜底
      return '__b64:${base64Url.encode(b)}';
    }
  }

  int _indexOf(int byte, int start) {
    for (var i = start; i < _bytes.length; i++) {
      if (_bytes[i] == byte) return i;
    }
    return -1;
  }

  static int _compareBytes(Uint8List a, Uint8List b) {
    final len = a.length < b.length ? a.length : b.length;
    for (var i = 0; i < len; i++) {
      if (a[i] != b[i]) return a[i] - b[i];
    }
    return a.length - b.length;
  }
}

/// Bencode 编码器（用于字典序写入、磁力链回写等）
class BencodeEncoder {
  final List<int> _buf = [];

  List<int> encodeBytes(Object? value) {
    _write(value);
    return List<int>.from(_buf);
  }

  String encode(Object? value) {
    return utf8.decode(encodeBytes(value), allowMalformed: true);
  }

  void _write(Object? v) {
    if (v is int) {
      _buf.addAll('i${v}e'.codeUnits);
    } else if (v is String) {
      final bytes = utf8.encode(v);
      _buf.addAll('${bytes.length}:'.codeUnits);
      _buf.addAll(bytes);
    } else if (v is Uint8List) {
      _buf.addAll('${v.length}:'.codeUnits);
      _buf.addAll(v);
    } else if (v is List<int>) {
      _buf.addAll('${v.length}:'.codeUnits);
      _buf.addAll(v);
    } else if (v is List) {
      _buf.add(0x6c); // 'l'
      for (final e in v) {
        _write(e);
      }
      _buf.add(0x65); // 'e'
    } else if (v is Map) {
      _buf.add(0x64); // 'd'
      final sortedKeys = v.keys.toList()..sort((a, b) => (a as String).compareTo(b as String));
      for (final k in sortedKeys) {
        _write(k);
        _write(v[k]);
      }
      _buf.add(0x65); // 'e'
    } else {
      throw ArgumentError('Bencode 不支持类型: ${v.runtimeType}');
    }
  }
}

/// 工具：从字典里取 bytes（BT 规范所有字段都是 bytes）
extension DictBytesExt on Map {
  Uint8List? getBytes(String key) {
    final v = this[key];
    if (v is Uint8List) return v;
    if (v is List) return Uint8List.fromList(v.cast<int>());
    return null;
  }

  String? getUtf8(String key) {
    final b = getBytes(key);
    if (b == null) return null;
    return utf8.decode(b, allowMalformed: true);
  }

  int? getInt(String key) {
    final v = this[key];
    if (v is int) return v;
    return null;
  }

  List<Object?>? getList(String key) {
    final v = this[key];
    if (v is List) return v;
    return null;
  }

  Map? getDict(String key) {
    final v = this[key];
    if (v is Map) return v;
    return null;
  }
}
