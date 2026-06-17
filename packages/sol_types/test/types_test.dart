import 'package:sol_types/sol_types.dart';
import 'package:test/test.dart';

void main() {
  group('IntType', () {
    test('uint256 ABI type', () {
      expect(uint256Type.abiType, 'uint256');
    });

    test('int8 min/max', () {
      const t = IntType(8);
      expect(t.min, BigInt.from(-128));
      expect(t.max, BigInt.from(127));
    });

    test('uint8 min/max', () {
      expect(uint8Type.min, BigInt.zero);
      expect(uint8Type.max, BigInt.from(255));
    });
  });

  group('isImplicitlyConvertible', () {
    test('uint8 → uint256 ok', () {
      expect(isImplicitlyConvertible(uint8Type, uint256Type), isTrue);
    });

    test('uint256 → uint8 not ok', () {
      expect(isImplicitlyConvertible(uint256Type, uint8Type), isFalse);
    });

    test('uint256 → int256 not ok (sign mismatch)', () {
      expect(isImplicitlyConvertible(uint256Type, int256Type), isFalse);
    });

    test('address → address payable not ok implicitly', () {
      expect(isImplicitlyConvertible(addressType, addressPayableType), isFalse);
    });
  });

  group('isExplicitlyConvertible', () {
    test('uint256 → address (160-bit only)', () {
      expect(isExplicitlyConvertible(const IntType(160, signed: false), addressType), isTrue);
      expect(isExplicitlyConvertible(uint256Type, addressType), isFalse);
    });
  });

  group('TupleType', () {
    test('ABI type string', () {
      final t = TupleType([uint256Type, addressType]);
      expect(t.abiType, '(uint256,address)');
    });

    test('encoded size = sum of components', () {
      final t = TupleType([uint256Type, uint8Type]);
      expect(t.abiEncodedSize, 64);
    });

    test('dynamic if any component is dynamic', () {
      final t = TupleType([uint256Type, stringType]);
      expect(t.isDynamic, isTrue);
    });
  });
}
