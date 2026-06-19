/// Recursive Length Prefix (RLP) encoding, the wire format Ethereum uses for
/// transactions (and most other consensus-critical structures).
///
/// See https://ethereum.org/en/developers/docs/data-structures-and-encoding/rlp/
library;

import 'dart:typed_data';

import 'codec.dart';

/// An RLP-encodable item: either a byte string ([RlpBytes]) or an ordered
/// list of items ([RlpList]). Mirrors the two cases the RLP spec defines.
sealed class RlpItem {
  const RlpItem();
}

class RlpBytes extends RlpItem {
  const RlpBytes(this.data);

  final Uint8List data;
}

class RlpList extends RlpItem {
  const RlpList(this.items);

  final List<RlpItem> items;
}

/// Encodes an unsigned integer per RLP convention: big-endian, no leading
/// zero bytes, and the empty byte string for zero.
RlpItem rlpUint(BigInt value) {
  if (value < BigInt.zero) {
    throw ArgumentError('RLP cannot encode negative integers, got $value');
  }
  if (value == BigInt.zero) return RlpBytes(Uint8List(0));
  var hex = value.toRadixString(16);
  if (hex.length.isOdd) hex = '0$hex';
  return RlpBytes(hexToBytes(hex));
}

/// Encodes [item] to its RLP byte representation.
Uint8List rlpEncode(RlpItem item) {
  switch (item) {
    case RlpBytes(data: final data):
      if (data.length == 1 && data[0] < 0x80) return data;
      return _withLengthPrefix(0x80, data);
    case RlpList(items: final items):
      final payload = _concat(items.map(rlpEncode).toList());
      return _withLengthPrefix(0xc0, payload);
  }
}

Uint8List _withLengthPrefix(int baseOffset, Uint8List payload) {
  if (payload.length < 56) {
    return Uint8List.fromList([baseOffset + payload.length, ...payload]);
  }
  var lengthHex = payload.length.toRadixString(16);
  if (lengthHex.length.isOdd) lengthHex = '0$lengthHex';
  final lengthBytes = hexToBytes(lengthHex);
  return Uint8List.fromList([
    baseOffset + 55 + lengthBytes.length,
    ...lengthBytes,
    ...payload,
  ]);
}

Uint8List _concat(List<Uint8List> parts) {
  final builder = BytesBuilder();
  for (final p in parts) {
    builder.add(p);
  }
  return builder.toBytes();
}

/// Decodes a single top-level RLP item from [data]. Throws a [FormatException]
/// if [data] contains anything other than exactly one encoded item.
///
/// Provided mainly so tests (and callers debugging a raw transaction) can
/// round-trip [rlpEncode] without re-deriving the field layout by hand.
RlpItem rlpDecode(Uint8List data) {
  final result = _decodeAt(data, 0);
  if (result.bytesConsumed != data.length) {
    throw FormatException('trailing bytes after top-level RLP item');
  }
  return result.item;
}

class _DecodeResult {
  const _DecodeResult(this.item, this.bytesConsumed);

  final RlpItem item;
  final int bytesConsumed;
}

_DecodeResult _decodeAt(Uint8List data, int offset) {
  final prefix = data[offset];
  if (prefix < 0x80) {
    return _DecodeResult(RlpBytes(Uint8List.fromList([prefix])), 1);
  }
  if (prefix < 0xb8) {
    final length = prefix - 0x80;
    return _DecodeResult(
      RlpBytes(data.sublist(offset + 1, offset + 1 + length)),
      1 + length,
    );
  }
  if (prefix < 0xc0) {
    final lengthOfLength = prefix - 0xb7;
    final length = _bytesToLength(
      data.sublist(offset + 1, offset + 1 + lengthOfLength),
    );
    final start = offset + 1 + lengthOfLength;
    return _DecodeResult(
      RlpBytes(data.sublist(start, start + length)),
      1 + lengthOfLength + length,
    );
  }
  if (prefix < 0xf8) {
    final length = prefix - 0xc0;
    return _DecodeResult(
      RlpList(_decodeList(data, offset + 1, length)),
      1 + length,
    );
  }
  final lengthOfLength = prefix - 0xf7;
  final length = _bytesToLength(
    data.sublist(offset + 1, offset + 1 + lengthOfLength),
  );
  final start = offset + 1 + lengthOfLength;
  return _DecodeResult(
    RlpList(_decodeList(data, start, length)),
    1 + lengthOfLength + length,
  );
}

List<RlpItem> _decodeList(Uint8List data, int start, int length) {
  final items = <RlpItem>[];
  var pos = start;
  final end = start + length;
  while (pos < end) {
    final result = _decodeAt(data, pos);
    items.add(result.item);
    pos += result.bytesConsumed;
  }
  return items;
}

int _bytesToLength(Uint8List bytes) {
  var v = 0;
  for (final b in bytes) {
    v = (v << 8) | b;
  }
  return v;
}
