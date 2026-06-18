import 'dart:typed_data';
import 'package:sol_types/sol_types.dart';

/// ABI-decodes bytes according to the Solidity ABI spec.
class AbiDecoder {
  /// Decodes [data] as a sequence of [types], returning one Dart value per type.
  ///
  /// Returned values:
  /// - IntType → BigInt
  /// - BoolType → bool
  /// - AddressType → BigInt (160-bit)
  /// - BytesNType → Uint8List (n bytes)
  /// - BytesType → Uint8List
  /// - StringType → String
  /// - ArrayType → List
  /// - TupleType → List
  List<Object?> decode(List<SolType> types, Uint8List data) {
    final result = <Object?>[];
    var headOffset = 0;
    for (final type in types) {
      if (type.isDynamic) {
        final pointer = _readUint(data, headOffset).toInt();
        result.add(_decodeValue(type, data, pointer));
        headOffset += 32;
      } else {
        result.add(_decodeValue(type, data, headOffset));
        headOffset += type.abiEncodedSize;
      }
    }
    return result;
  }

  Object? _decodeValue(SolType type, Uint8List data, int offset) {
    switch (type) {
      case IntType(:final bits, :final signed):
        var n = _readUint(data, offset);
        if (signed && n >= (BigInt.one << (bits - 1))) {
          n -= BigInt.one << bits;
        }
        return n;
      case BoolType():
        return _readUint(data, offset) != BigInt.zero;
      case AddressType():
        return _readUint(data, offset) & ((BigInt.one << 160) - BigInt.one);
      case BytesNType(:final n):
        final bytes = Uint8List(n);
        for (var i = 0; i < n; i++) {
          bytes[i] = (offset + i) < data.length ? data[offset + i] : 0;
        }
        return bytes;
      case BytesType():
        final len = _readUint(data, offset).toInt();
        return Uint8List.fromList(data.sublist(offset + 32, offset + 32 + len));
      case StringType():
        final len = _readUint(data, offset).toInt();
        final bytes = data.sublist(offset + 32, offset + 32 + len);
        return String.fromCharCodes(bytes);
      case ArrayType(:final elementType, :final length):
        int count;
        int dataStart;
        if (length == null) {
          count = _readUint(data, offset).toInt();
          dataStart = offset + 32;
        } else {
          count = length;
          dataStart = offset;
        }
        return [
          for (var i = 0; i < count; i++)
            if (elementType.isDynamic)
              _decodeValue(
                elementType,
                data,
                dataStart + _readUint(data, dataStart + i * 32).toInt(),
              )
            else
              _decodeValue(
                elementType,
                data,
                dataStart + i * elementType.abiEncodedSize,
              ),
        ];
      case TupleType(:final components):
        final result = <Object?>[];
        var pos = offset;
        for (final comp in components) {
          if (comp.isDynamic) {
            final ptr = _readUint(data, pos).toInt();
            result.add(_decodeValue(comp, data, offset + ptr));
            pos += 32;
          } else {
            result.add(_decodeValue(comp, data, pos));
            pos += comp.abiEncodedSize;
          }
        }
        return result;
      default:
        throw UnsupportedError(
          'ABI decoding not implemented for ${type.abiType}',
        );
    }
  }

  static BigInt _readUint(Uint8List data, int offset) {
    var result = BigInt.zero;
    for (var i = 0; i < 32; i++) {
      final b = (offset + i) < data.length ? data[offset + i] : 0;
      result = (result << 8) | BigInt.from(b);
    }
    return result;
  }
}
