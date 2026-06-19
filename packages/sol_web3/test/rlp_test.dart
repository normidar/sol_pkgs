import 'dart:typed_data';

import 'package:sol_web3/sol_web3.dart';
import 'package:test/test.dart';

void main() {
  group('rlpEncode', () {
    // Canonical vectors from the RLP spec / Ethereum wiki.
    test('the empty string encodes to 0x80', () {
      expect(rlpEncode(RlpBytes(Uint8List(0))), [0x80]);
    });

    test('a single byte < 0x80 encodes to itself', () {
      expect(rlpEncode(RlpBytes(Uint8List.fromList([0x00]))), [0x00]);
      expect(rlpEncode(RlpBytes(Uint8List.fromList([0x7f]))), [0x7f]);
    });

    test('"dog" encodes to 0x83646f67', () {
      final bytes = Uint8List.fromList('dog'.codeUnits);
      expect(bytesToHex(rlpEncode(RlpBytes(bytes))), '83646f67');
    });

    test('["cat", "dog"] encodes to 0xc88363617483646f67', () {
      final list = RlpList([
        RlpBytes(Uint8List.fromList('cat'.codeUnits)),
        RlpBytes(Uint8List.fromList('dog'.codeUnits)),
      ]);
      expect(bytesToHex(rlpEncode(list)), 'c88363617483646f67');
    });

    test('the empty list encodes to 0xc0', () {
      expect(rlpEncode(const RlpList([])), [0xc0]);
    });

    test('a string of exactly 56 bytes uses the long-string prefix', () {
      final bytes = Uint8List(56);
      final encoded = rlpEncode(RlpBytes(bytes));
      expect(encoded[0], 0xb8);
      expect(encoded[1], 56);
      expect(encoded.length, 2 + 56);
    });

    test('a list whose payload is >= 56 bytes uses the long-list prefix', () {
      final items = List.generate(
        20,
        (i) => RlpBytes(Uint8List.fromList([i, i])),
      );
      final encoded = rlpEncode(RlpList(items));
      expect(encoded[0], greaterThanOrEqualTo(0xf8));
    });
  });

  group('rlpUint', () {
    test('zero encodes as the empty byte string', () {
      expect(rlpEncode(rlpUint(BigInt.zero)), [0x80]);
    });

    test('15 (0x0f) encodes as itself (single byte < 0x80)', () {
      expect(rlpEncode(rlpUint(BigInt.from(15))), [0x0f]);
    });

    test('1024 encodes with minimal big-endian bytes', () {
      // 1024 = 0x0400 -> minimal bytes 0x04 0x00 -> RLP: 0x82 0x04 0x00
      expect(rlpEncode(rlpUint(BigInt.from(1024))), [0x82, 0x04, 0x00]);
    });

    test('rejects negative values', () {
      expect(() => rlpUint(BigInt.from(-1)), throwsArgumentError);
    });
  });

  group('rlpDecode', () {
    test('round-trips a byte string', () {
      final original = RlpBytes(Uint8List.fromList('dog'.codeUnits));
      final decoded = rlpDecode(rlpEncode(original)) as RlpBytes;
      expect(decoded.data, original.data);
    });

    test('round-trips a nested list', () {
      final original = RlpList([
        RlpBytes(Uint8List.fromList('cat'.codeUnits)),
        RlpList([
          RlpBytes(Uint8List.fromList([1, 2, 3])),
        ]),
      ]);
      final decoded = rlpDecode(rlpEncode(original)) as RlpList;
      expect(decoded.items, hasLength(2));
      expect((decoded.items[0] as RlpBytes).data, 'cat'.codeUnits);
      final inner = decoded.items[1] as RlpList;
      expect((inner.items[0] as RlpBytes).data, [1, 2, 3]);
    });

    test('round-trips a long (>55 byte) string', () {
      final bytes = Uint8List.fromList(List.generate(200, (i) => i % 256));
      final decoded = rlpDecode(rlpEncode(RlpBytes(bytes))) as RlpBytes;
      expect(decoded.data, bytes);
    });

    test('throws on trailing bytes after the top-level item', () {
      final encoded = rlpEncode(RlpBytes(Uint8List.fromList('dog'.codeUnits)));
      final withTrailingByte = Uint8List.fromList([...encoded, 0x00]);
      expect(() => rlpDecode(withTrailingByte), throwsFormatException);
    });
  });
}
