/// ABI decoding of `eth_getLogs` entries into typed Dart values.
library;

import 'dart:typed_data';

import 'package:sol_types/sol_types.dart';

import 'codec.dart';
import 'eth_client.dart';

/// Describes one parameter of a Solidity event, pairing its ABI type with
/// the `indexed` flag.
class EventParam {
  const EventParam(this.type, {this.indexed = false});

  final SolType type;

  /// Whether this parameter carries the `indexed` modifier in Solidity.
  final bool indexed;
}

/// Decodes a raw [EventLog] into a list of typed Dart values according to
/// [params].
///
/// Decoding rules:
/// - `topics[0]` is always the event-signature hash and is not included in
///   the returned list.
/// - Indexed params with static types (integers, bool, address, bytesN) are
///   decoded from the next `topics[N]` slot.
/// - Indexed params with dynamic types (bytes, string, arrays, tuples) cannot
///   be recovered because the EVM stores only the keccak256 hash; the raw
///   32-byte [Uint8List] is returned instead.
/// - Non-indexed params are ABI-decoded from `log.data`.
///
/// Return types per [SolType]:
/// - [IntType] → [BigInt]
/// - [BoolType] → [bool]
/// - [AddressType] → [BigInt] (160-bit)
/// - [BytesNType] → [Uint8List] (n bytes)
/// - [BytesType] → [Uint8List]
/// - [StringType] → [String]
/// - [ArrayType] → [List]
/// - [TupleType] → [List]
List<Object?> decodeEventLog(EventLog log, List<EventParam> params) {
  final result = List<Object?>.filled(params.length, null);
  final indexedSlots = <int>[];
  final nonIndexedSlots = <int>[];

  for (var i = 0; i < params.length; i++) {
    (params[i].indexed ? indexedSlots : nonIndexedSlots).add(i);
  }

  if (nonIndexedSlots.isNotEmpty) {
    final types = [for (final i in nonIndexedSlots) params[i].type];
    final decoded = _decodeAbi(types, log.data);
    for (var j = 0; j < nonIndexedSlots.length; j++) {
      result[nonIndexedSlots[j]] = decoded[j];
    }
  }

  for (var j = 0; j < indexedSlots.length; j++) {
    final paramIdx = indexedSlots[j];
    final topicIdx = j + 1; // topics[0] = event signature hash
    if (topicIdx >= log.topics.length) break;
    final topicBytes = hexToBytes(log.topics[topicIdx]);
    final type = params[paramIdx].type;
    result[paramIdx] = type.isDynamic
        ? topicBytes // keccak256 hash only; original value not recoverable
        : _decodeStatic(type, topicBytes, 0);
  }

  return result;
}

List<Object?> _decodeAbi(List<SolType> types, Uint8List data) {
  final result = <Object?>[];
  var head = 0;
  for (final type in types) {
    if (type.isDynamic) {
      final ptr = _readUint(data, head).toInt();
      result.add(_decodeDynamic(type, data, ptr));
      head += 32;
    } else {
      result.add(_decodeStatic(type, data, head));
      head += type.abiEncodedSize;
    }
  }
  return result;
}

Object? _decodeStatic(SolType type, Uint8List data, int offset) {
  switch (type) {
    case IntType(:final bits, :final signed):
      var n = _readUint(data, offset);
      if (signed && n >= (BigInt.one << (bits - 1))) n -= BigInt.one << bits;
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
    case ArrayType(:final elementType, :final length):
      return [
        for (var i = 0; i < length!; i++)
          _decodeStatic(
            elementType,
            data,
            offset + i * elementType.abiEncodedSize,
          ),
      ];
    case TupleType(:final components):
      final items = <Object?>[];
      var pos = offset;
      for (final comp in components) {
        items.add(_decodeStatic(comp, data, pos));
        pos += comp.abiEncodedSize;
      }
      return items;
    default:
      throw UnsupportedError('Cannot static-decode ${type.abiType}');
  }
}

Object? _decodeDynamic(SolType type, Uint8List data, int offset) {
  switch (type) {
    case BytesType():
      final len = _readUint(data, offset).toInt();
      return Uint8List.fromList(data.sublist(offset + 32, offset + 32 + len));
    case StringType():
      final len = _readUint(data, offset).toInt();
      return String.fromCharCodes(data.sublist(offset + 32, offset + 32 + len));
    case ArrayType(:final elementType, length: null):
      final count = _readUint(data, offset).toInt();
      final dataStart = offset + 32;
      return [
        for (var i = 0; i < count; i++)
          if (elementType.isDynamic)
            _decodeDynamic(
              elementType,
              data,
              dataStart + _readUint(data, dataStart + i * 32).toInt(),
            )
          else
            _decodeStatic(
              elementType,
              data,
              dataStart + i * elementType.abiEncodedSize,
            ),
      ];
    case TupleType(:final components):
      final items = <Object?>[];
      var pos = offset;
      for (final comp in components) {
        if (comp.isDynamic) {
          final ptr = _readUint(data, pos).toInt();
          items.add(_decodeDynamic(comp, data, offset + ptr));
          pos += 32;
        } else {
          items.add(_decodeStatic(comp, data, pos));
          pos += comp.abiEncodedSize;
        }
      }
      return items;
    default:
      throw UnsupportedError('Cannot dynamic-decode ${type.abiType}');
  }
}

BigInt _readUint(Uint8List data, int offset) {
  var result = BigInt.zero;
  for (var i = 0; i < 32; i++) {
    final b = (offset + i) < data.length ? data[offset + i] : 0;
    result = (result << 8) | BigInt.from(b);
  }
  return result;
}
