/// Tests for decodeEventLog: typed decoding of eth_getLogs entries.
library;

import 'dart:typed_data';

import 'package:sol_types/sol_types.dart';
import 'package:sol_web3/sol_web3.dart';
import 'package:test/test.dart';

// Builds a 32-byte big-endian encoding of [value], padded left with zeros.
Uint8List _word(BigInt value) {
  final out = Uint8List(32);
  var v = value;
  for (var i = 31; i >= 0; i--) {
    out[i] = (v & BigInt.from(0xff)).toInt();
    v >>= 8;
  }
  return out;
}

Uint8List _wordInt(int value) => _word(BigInt.from(value));

String _hex(List<int> bytes) {
  final sb = StringBuffer('0x');
  for (final b in bytes) {
    sb.write((b & 0xff).toRadixString(16).padLeft(2, '0'));
  }
  return sb.toString();
}

String _repeat(String s, int n) => List.filled(n, s).join();

// Builds a minimal EventLog for testing.
EventLog _makeLog({List<String> topics = const [], Uint8List? data}) =>
    EventLog(
      address: EthAddress.fromHex('0x1111111111111111111111111111111111111111'),
      topics: topics,
      data: data ?? Uint8List(0),
      blockNumber: BigInt.one,
      transactionHash: '0x${_repeat('aa', 32)}',
      transactionIndex: 0,
      blockHash: '0x${_repeat('bb', 32)}',
      logIndex: 0,
      removed: false,
    );

void main() {
  group('decodeEventLog — non-indexed params', () {
    test('decodes a single uint256 from data', () {
      final data = _wordInt(42);
      final log = _makeLog(topics: ['0x${_repeat('ef', 32)}'], data: data);
      final result = decodeEventLog(log, [
        const EventParam(IntType(256, signed: false)),
      ]);
      expect(result, [BigInt.from(42)]);
    });

    test('decodes bool from data', () {
      final data = _wordInt(1);
      final log = _makeLog(topics: ['0x${_repeat('00', 32)}'], data: data);
      final result = decodeEventLog(log, [const EventParam(BoolType())]);
      expect(result, [true]);
    });

    test('decodes address from data', () {
      final addrBigInt = BigInt.parse(
        'abcdefabcdefabcdefabcdefabcdefabcdefabcd',
        radix: 16,
      );
      final data = _word(addrBigInt);
      final log = _makeLog(topics: ['0x${_repeat('00', 32)}'], data: data);
      final result = decodeEventLog(log, [const EventParam(AddressType())]);
      expect(result[0], addrBigInt);
    });

    test('decodes two uint256 values from data', () {
      final data = Uint8List(64)
        ..setRange(0, 32, _wordInt(100))
        ..setRange(32, 64, _wordInt(200));
      final log = _makeLog(topics: ['0x${_repeat('ab', 32)}'], data: data);
      final result = decodeEventLog(log, [
        const EventParam(IntType(256, signed: false)),
        const EventParam(IntType(256, signed: false)),
      ]);
      expect(result, [BigInt.from(100), BigInt.from(200)]);
    });

    test('decodes string from data', () {
      // ABI encoding of "hello":
      // offset(32) + length(5) + "hello" padded to 32
      final strBytes = 'hello'.codeUnits;
      final data = Uint8List(96);
      data.setRange(0, 32, _wordInt(32)); // offset to string data
      data.setRange(32, 64, _wordInt(5)); // length
      data.setRange(64, 64 + strBytes.length, strBytes);
      final log = _makeLog(topics: ['0x${_repeat('00', 32)}'], data: data);
      final result = decodeEventLog(log, [const EventParam(StringType())]);
      expect(result, ['hello']);
    });

    test('decodes bytes from data', () {
      final payload = [0xde, 0xad, 0xbe, 0xef];
      final data = Uint8List(96);
      data.setRange(0, 32, _wordInt(32)); // offset
      data.setRange(32, 64, _wordInt(4)); // length
      data.setRange(64, 68, payload);
      final log = _makeLog(topics: ['0x${_repeat('00', 32)}'], data: data);
      final result = decodeEventLog(log, [const EventParam(BytesType())]);
      expect(result[0], isA<Uint8List>());
      expect(result[0] as Uint8List, Uint8List.fromList(payload));
    });

    test('decodes signed int256 (negative) from data', () {
      const bits = 256;
      final neg = BigInt.from(-1);
      // two's complement of -1 is all 0xff bytes
      final twos = neg + (BigInt.one << bits);
      final data = _word(twos);
      final log = _makeLog(topics: ['0x${_repeat('00', 32)}'], data: data);
      final result = decodeEventLog(log, [
        const EventParam(IntType(256, signed: true)),
      ]);
      expect(result, [neg]);
    });
  });

  group('decodeEventLog — indexed params', () {
    test('decodes indexed uint256 from topic', () {
      final sigHash = '0x${_repeat('ef', 32)}';
      final topic1 = _hex(_wordInt(999));
      final log = _makeLog(topics: [sigHash, topic1], data: Uint8List(0));
      final result = decodeEventLog(log, [
        const EventParam(IntType(256, signed: false), indexed: true),
      ]);
      expect(result, [BigInt.from(999)]);
    });

    test('decodes indexed bool from topic', () {
      final sigHash = '0x${_repeat('ef', 32)}';
      final topic1 = _hex(_wordInt(1));
      final log = _makeLog(topics: [sigHash, topic1]);
      final result = decodeEventLog(log, [
        const EventParam(BoolType(), indexed: true),
      ]);
      expect(result, [true]);
    });

    test('decodes indexed address from topic', () {
      final addr = BigInt.parse(
        '1234567890123456789012345678901234567890',
        radix: 16,
      );
      final sigHash = '0x${_repeat('ef', 32)}';
      final topic1 = _hex(_word(addr));
      final log = _makeLog(topics: [sigHash, topic1]);
      final result = decodeEventLog(log, [
        const EventParam(AddressType(), indexed: true),
      ]);
      expect(result[0], addr & ((BigInt.one << 160) - BigInt.one));
    });

    test('indexed dynamic type returns raw 32-byte hash', () {
      final sigHash = '0x${_repeat('ef', 32)}';
      final hashBytes = List.generate(32, (i) => i + 1);
      final topic1 = _hex(hashBytes);
      final log = _makeLog(topics: [sigHash, topic1]);
      final result = decodeEventLog(log, [
        const EventParam(StringType(), indexed: true),
      ]);
      expect(result[0], isA<Uint8List>());
      expect((result[0] as Uint8List).length, 32);
    });
  });

  group('decodeEventLog — mixed indexed and non-indexed', () {
    test(
      'Transfer(address indexed from, address indexed to, uint256 value)',
      () {
        // ERC-20 Transfer event
        // topics[0] = Transfer signature hash (ignored)
        // topics[1] = from address (indexed)
        // topics[2] = to address (indexed)
        // data = amount (non-indexed)

        final from = BigInt.parse(
          '1111111111111111111111111111111111111111',
          radix: 16,
        );
        final to = BigInt.parse(
          '2222222222222222222222222222222222222222',
          radix: 16,
        );
        final amount = BigInt.parse('1000000000000000000'); // 1e18

        const sigHash =
            '0xddf252ad1be2c89b69c2b068fc378daa952ba7f163c4a11628f55a4df523b3ef';
        final log = _makeLog(
          topics: [sigHash, _hex(_word(from)), _hex(_word(to))],
          data: _word(amount),
        );

        final result = decodeEventLog(log, [
          const EventParam(AddressType(), indexed: true), // from
          const EventParam(AddressType(), indexed: true), // to
          const EventParam(IntType(256, signed: false)), // value
        ]);

        expect(result[0], from);
        expect(result[1], to);
        expect(result[2], amount);
      },
    );

    test('decodes mixed order: non-indexed first, indexed second', () {
      final sigHash = '0x${_repeat('ef', 32)}';
      final topic1 = _hex(_wordInt(7));
      final data = _wordInt(42);
      final log = _makeLog(topics: [sigHash, topic1], data: data);

      final result = decodeEventLog(log, [
        const EventParam(IntType(256, signed: false)), // non-indexed
        const EventParam(IntType(256, signed: false), indexed: true),
      ]);
      expect(result[0], BigInt.from(42)); // from data
      expect(result[1], BigInt.from(7)); // from topic[1]
    });
  });

  group('decodeEventLog — bytesN indexed', () {
    test('decodes indexed bytes32 from topic', () {
      final payload = List.generate(32, (i) => i);
      final sigHash = '0x${_repeat('ef', 32)}';
      final topic1 = _hex(payload);
      final log = _makeLog(topics: [sigHash, topic1]);
      final result = decodeEventLog(log, [
        const EventParam(BytesNType(32), indexed: true),
      ]);
      expect(result[0], isA<Uint8List>());
      expect(result[0] as Uint8List, Uint8List.fromList(payload));
    });
  });
}
