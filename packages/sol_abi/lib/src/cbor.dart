/// Minimal CBOR (RFC 8949) encoder, just the constructs solc uses to append
/// contract metadata to bytecode: unsigned ints, byte strings, text strings,
/// and definite-length maps.
///
/// solc appends to runtime bytecode:
/// ```
///   <cbor map>  <2-byte big-endian length of the cbor map>
/// ```
/// The map (with `bytecodeHash: ipfs`) typically contains
/// `{"ipfs": <hash>, "solc": <3-byte version>}`.
///
/// We do not implement decoding here — verification tools have their own.
library;

import 'dart:typed_data';

/// Encodes a small subset of CBOR sufficient for metadata blobs.
///
/// Supported value types:
/// - `int` (non-negative, fits in 64 bits) → unsigned int
/// - `String` → UTF-8 text string
/// - `List<int>` / `Uint8List` → byte string
/// - `Map<String, dynamic>` → map with text-string keys, encoded in
///   user-specified iteration order (solc emits keys sorted alphabetically)
Uint8List encodeCbor(Object value) {
  final out = BytesBuilder(copy: false);
  _encode(out, value);
  return out.toBytes();
}

void _encode(BytesBuilder out, Object value) {
  if (value is int) {
    if (value < 0) {
      throw ArgumentError('Negative ints not supported by metadata CBOR');
    }
    _writeHead(out, 0, value);
  } else if (value is String) {
    final bytes = _utf8(value);
    _writeHead(out, 3, bytes.length);
    out.add(bytes);
  } else if (value is Uint8List) {
    _writeHead(out, 2, value.length);
    out.add(value);
  } else if (value is List<int>) {
    final b = Uint8List.fromList(value);
    _writeHead(out, 2, b.length);
    out.add(b);
  } else if (value is Map) {
    _writeHead(out, 5, value.length);
    value.forEach((k, v) {
      if (k is! String) {
        throw ArgumentError('CBOR map keys must be strings here, got $k');
      }
      _encode(out, k);
      _encode(out, v as Object);
    });
  } else {
    throw ArgumentError('Unsupported CBOR value: ${value.runtimeType}');
  }
}

/// Writes the CBOR initial byte plus the optional argument bytes.
///
/// [major] is the 3-bit major type (0..7); [arg] is the unsigned value.
void _writeHead(BytesBuilder out, int major, int arg) {
  final m = (major & 0x7) << 5;
  if (arg < 24) {
    out.addByte(m | arg);
  } else if (arg < 0x100) {
    out.addByte(m | 24);
    out.addByte(arg);
  } else if (arg < 0x10000) {
    out.addByte(m | 25);
    out.addByte((arg >> 8) & 0xff);
    out.addByte(arg & 0xff);
  } else if (arg < 0x100000000) {
    out.addByte(m | 26);
    out.addByte((arg >> 24) & 0xff);
    out.addByte((arg >> 16) & 0xff);
    out.addByte((arg >> 8) & 0xff);
    out.addByte(arg & 0xff);
  } else {
    out.addByte(m | 27);
    for (var i = 7; i >= 0; i--) {
      out.addByte((arg >> (i * 8)) & 0xff);
    }
  }
}

Uint8List _utf8(String s) {
  // Restrict to ASCII for the metadata fields we emit ("solc", "soldart",
  // "keccak256"); cheaper than dragging in dart:convert here.
  final out = Uint8List(s.length);
  for (var i = 0; i < s.length; i++) {
    final c = s.codeUnitAt(i);
    if (c > 0x7f) {
      throw ArgumentError('Non-ASCII text in metadata CBOR: $s');
    }
    out[i] = c;
  }
  return out;
}
