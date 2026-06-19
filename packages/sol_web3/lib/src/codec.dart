/// Byte/hex/[BigInt] conversion helpers shared by the RLP, transaction, and
/// JSON-RPC layers.
library;

import 'dart:typed_data';

/// Parses [hex] (with or without a `0x` prefix) into bytes. An odd number of
/// hex digits is left-padded with a zero nibble.
Uint8List hexToBytes(String hex) {
  var h = (hex.startsWith('0x') || hex.startsWith('0X'))
      ? hex.substring(2)
      : hex;
  if (h.isEmpty) return Uint8List(0);
  if (h.length.isOdd) h = '0$h';
  final out = Uint8List(h.length ~/ 2);
  for (var i = 0; i < out.length; i++) {
    out[i] = int.parse(h.substring(i * 2, i * 2 + 2), radix: 16);
  }
  return out;
}

/// Renders [bytes] as lowercase hex, optionally with a `0x` prefix.
String bytesToHex(List<int> bytes, {bool include0x = false}) {
  final sb = StringBuffer(include0x ? '0x' : '');
  for (final b in bytes) {
    sb.write((b & 0xff).toRadixString(16).padLeft(2, '0'));
  }
  return sb.toString();
}

/// Interprets [bytes] as a big-endian unsigned integer.
BigInt bytesToBigInt(List<int> bytes) {
  var result = BigInt.zero;
  for (final b in bytes) {
    result = (result << 8) | BigInt.from(b & 0xff);
  }
  return result;
}

/// Encodes [value] as exactly [length] big-endian bytes.
Uint8List bigIntToBytes(BigInt value, int length) {
  final out = Uint8List(length);
  var v = value;
  for (var i = length - 1; i >= 0; i--) {
    out[i] = (v & BigInt.from(0xff)).toInt();
    v >>= 8;
  }
  return out;
}

/// Ethereum JSON-RPC "quantity" encoding: minimal hex, no leading zeros,
/// `0x0` for zero.
///
/// See https://ethereum.org/en/developers/docs/apis/json-rpc/#hex-value-encoding
String bigIntToHex(BigInt value) => '0x${value.toRadixString(16)}';

/// Parses an Ethereum JSON-RPC "quantity" hex string back into a [BigInt].
BigInt bigIntFromHex(String hex) {
  final h = (hex.startsWith('0x') || hex.startsWith('0X'))
      ? hex.substring(2)
      : hex;
  return h.isEmpty ? BigInt.zero : BigInt.parse(h, radix: 16);
}
