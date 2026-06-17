import 'dart:typed_data';
import 'package:sol_types/sol_types.dart';

/// ABI-encodes Dart values according to the Solidity ABI spec.
///
/// See https://docs.soliditylang.org/en/latest/abi-spec.html
class AbiEncoder {
  /// Encodes a list of (type, value) pairs according to `eth_abi` rules.
  Uint8List encode(List<(SolType, Object?)> args) {
    final heads = <Uint8List>[];
    final tails = <Uint8List>[];
    var tailOffset = args.length * 32;

    for (final (type, value) in args) {
      if (type.isDynamic) {
        heads.add(_encodeUint(BigInt.from(tailOffset)));
        final tail = _encodeValue(type, value);
        tails.add(tail);
        tailOffset += tail.length;
      } else {
        heads.add(_encodeValue(type, value));
      }
    }

    final builder = BytesBuilder();
    for (final h in heads) builder.add(h);
    for (final t in tails) builder.add(t);
    return builder.toBytes();
  }

  Uint8List _encodeValue(SolType type, Object? value) {
    switch (type) {
      case IntType(:final bits, :final signed):
        final n = _toBigInt(value);
        return _encodeUint(signed ? _toTwosComplement(n, bits) : n);

      case BoolType():
        return _encodeUint(value == true ? BigInt.one : BigInt.zero);

      case AddressType():
        final n = _toBigInt(value);
        return _encodeUint(n & ((BigInt.one << 160) - BigInt.one));

      case BytesNType(:final n):
        final bytes = _toBytes(value);
        final padded = Uint8List(32);
        padded.setRange(0, bytes.length.clamp(0, n), bytes);
        return padded;

      case BytesType():
        final bytes = _toBytes(value);
        final builder = BytesBuilder();
        builder.add(_encodeUint(BigInt.from(bytes.length)));
        builder.add(bytes);
        // pad to 32-byte boundary
        final pad = (32 - bytes.length % 32) % 32;
        builder.add(Uint8List(pad));
        return builder.toBytes();

      case StringType():
        final bytes = Uint8List.fromList(
            (value as String).codeUnits.map((c) => c & 0xFF).toList());
        final builder = BytesBuilder();
        builder.add(_encodeUint(BigInt.from(bytes.length)));
        builder.add(bytes);
        final pad = (32 - bytes.length % 32) % 32;
        builder.add(Uint8List(pad));
        return builder.toBytes();

      case ArrayType(:final elementType, :final length):
        final list = value as List;
        final builder = BytesBuilder();
        if (length == null) {
          builder.add(_encodeUint(BigInt.from(list.length)));
        }
        for (final item in list) {
          builder.add(_encodeValue(elementType, item));
        }
        return builder.toBytes();

      default:
        throw UnsupportedError('ABI encoding not implemented for ${type.abiType}');
    }
  }

  static Uint8List _encodeUint(BigInt value) {
    final bytes = Uint8List(32);
    var v = value;
    for (var i = 31; i >= 0; i--) {
      bytes[i] = (v & BigInt.from(0xFF)).toInt();
      v >>= 8;
    }
    return bytes;
  }

  static BigInt _toTwosComplement(BigInt value, int bits) {
    if (value >= BigInt.zero) return value;
    return value + (BigInt.one << bits);
  }

  static BigInt _toBigInt(Object? value) {
    if (value is BigInt) return value;
    if (value is int) return BigInt.from(value);
    if (value is String) {
      if (value.startsWith('0x')) return BigInt.parse(value.substring(2), radix: 16);
      return BigInt.parse(value);
    }
    return BigInt.zero;
  }

  static Uint8List _toBytes(Object? value) {
    if (value is Uint8List) return value;
    if (value is List<int>) return Uint8List.fromList(value);
    if (value is String) {
      if (value.startsWith('0x')) {
        final hex = value.substring(2);
        final bytes = Uint8List(hex.length ~/ 2);
        for (var i = 0; i < bytes.length; i++) {
          bytes[i] = int.parse(hex.substring(i * 2, i * 2 + 2), radix: 16);
        }
        return bytes;
      }
      return Uint8List.fromList(value.codeUnits);
    }
    return Uint8List(0);
  }
}
