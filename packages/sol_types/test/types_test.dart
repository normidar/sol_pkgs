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
      expect(
        isExplicitlyConvertible(const IntType(160, signed: false), addressType),
        isTrue,
      );
      expect(isExplicitlyConvertible(uint256Type, addressType), isFalse);
    });
  });

  group('FixedType', () {
    test('signed ABI type', () {
      expect(const FixedType(128, 18).abiType, 'fixed128x18');
    });

    test('unsigned ABI type', () {
      expect(const FixedType(128, 18, signed: false).abiType, 'ufixed128x18');
    });

    test('aliases default to 128x18', () {
      expect(fixed128x18Type.abiType, 'fixed128x18');
      expect(ufixed128x18Type.abiType, 'ufixed128x18');
    });

    test('value equality', () {
      expect(const FixedType(64, 10), const FixedType(64, 10));
      expect(const FixedType(64, 10) == const FixedType(64, 8), isFalse);
    });

    test('implicit widening, same sign only', () {
      expect(
        isImplicitlyConvertible(
          const FixedType(64, 10),
          const FixedType(128, 18),
        ),
        isTrue,
      );
      // Narrowing not allowed.
      expect(
        isImplicitlyConvertible(
          const FixedType(128, 18),
          const FixedType(64, 10),
        ),
        isFalse,
      );
      // Sign mismatch not allowed.
      expect(
        isImplicitlyConvertible(
          const FixedType(128, 18),
          const FixedType(128, 18, signed: false),
        ),
        isFalse,
      );
    });

    test('explicit cast between any fixed types', () {
      expect(
        isExplicitlyConvertible(
          const FixedType(128, 18),
          const FixedType(64, 10),
        ),
        isTrue,
      );
    });
  });

  group('RationalNumberType', () {
    test('reduces to lowest terms', () {
      final r = RationalNumberType(BigInt.from(4), BigInt.from(8));
      expect(r.numerator, BigInt.one);
      expect(r.denominator, BigInt.two);
    });

    test('normalises sign onto numerator', () {
      final r = RationalNumberType(BigInt.from(1), BigInt.from(-2));
      expect(r.numerator, BigInt.from(-1));
      expect(r.denominator, BigInt.two);
      expect(r.isNegative, isTrue);
    });

    test('integer literal has denominator 1', () {
      final r = RationalNumberType.integer(BigInt.from(255));
      expect(r.isInteger, isTrue);
      expect(r.mobileIntType, uint8Type);
    });

    test('mobile type widens to fit', () {
      final r = RationalNumberType.integer(BigInt.from(256));
      expect(r.mobileIntType, const IntType(16, signed: false));
    });

    test('negative integer picks signed type', () {
      final r = RationalNumberType.integer(BigInt.from(-1));
      expect(r.mobileIntType, const IntType(8));
    });

    test('integer literal implicitly converts when it fits', () {
      final r = RationalNumberType.integer(BigInt.from(200));
      expect(isImplicitlyConvertible(r, uint8Type), isTrue);
      expect(isImplicitlyConvertible(r, uint256Type), isTrue);
    });

    test('integer literal that overflows does not convert', () {
      final r = RationalNumberType.integer(BigInt.from(256));
      expect(isImplicitlyConvertible(r, uint8Type), isFalse);
    });

    test('fractional literal converts to representable fixed type', () {
      // 0.5 = 5 * 10^-1, exactly representable with >=1 fractional digit.
      final half = RationalNumberType(BigInt.one, BigInt.two);
      expect(half.isInteger, isFalse);
      expect(isImplicitlyConvertible(half, const FixedType(128, 18)), isTrue);
      // 0 fractional digits cannot represent 0.5.
      expect(isImplicitlyConvertible(half, const FixedType(128, 0)), isFalse);
    });

    test('value equality', () {
      expect(
        RationalNumberType(BigInt.one, BigInt.two),
        RationalNumberType(BigInt.from(2), BigInt.from(4)),
      );
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
