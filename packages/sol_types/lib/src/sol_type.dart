/// Abstract base for all Solidity types.
abstract class SolType {
  const SolType();

  /// Canonical ABI type string, e.g. `uint256`, `address`, `bytes32`.
  String get abiType;

  /// Number of storage slots (32-byte words) occupied at rest.
  int get storageSlots => 1;

  /// Byte size of the ABI-encoded value (0 = dynamic).
  int get abiEncodedSize;

  bool get isDynamic => abiEncodedSize == 0;

  @override
  String toString() => abiType;
}

// ── Integer types ─────────────────────────────────────────────────────────────

class IntType extends SolType {
  const IntType(this.bits, {this.signed = true})
    : assert(bits >= 8 && bits <= 256 && bits % 8 == 0);

  final int bits;
  final bool signed;

  @override
  String get abiType => '${signed ? 'int' : 'uint'}$bits';

  @override
  int get abiEncodedSize => 32; // always padded to 32 bytes in ABI

  BigInt get min => signed ? -(BigInt.one << (bits - 1)) : BigInt.zero;

  BigInt get max => signed
      ? (BigInt.one << (bits - 1)) - BigInt.one
      : (BigInt.one << bits) - BigInt.one;

  @override
  bool operator ==(Object other) =>
      other is IntType && other.bits == bits && other.signed == signed;

  @override
  int get hashCode => Object.hash(bits, signed);
}

const uint8Type = IntType(8, signed: false);
const uint256Type = IntType(256, signed: false);
const int256Type = IntType(256, signed: true);

// ── Fixed-point types ───────────────────────────────────────────────────────

/// Signed (`fixedMxN`) and unsigned (`ufixedMxN`) fixed-point types.
///
/// `M` ([bits]) is the number of bits (8–256, multiple of 8) and `N`
/// ([fractionalDigits]) is the number of decimal places after the point
/// (0–80). The bare `fixed` / `ufixed` aliases mean `fixed128x18` /
/// `ufixed128x18`.
class FixedType extends SolType {
  const FixedType(this.bits, this.fractionalDigits, {this.signed = true})
    : assert(bits >= 8 && bits <= 256 && bits % 8 == 0),
      assert(fractionalDigits >= 0 && fractionalDigits <= 80);

  final int bits;
  final int fractionalDigits;
  final bool signed;

  @override
  String get abiType =>
      '${signed ? 'fixed' : 'ufixed'}${bits}x$fractionalDigits';

  @override
  int get abiEncodedSize => 32;

  @override
  bool operator ==(Object other) =>
      other is FixedType &&
      other.bits == bits &&
      other.fractionalDigits == fractionalDigits &&
      other.signed == signed;

  @override
  int get hashCode => Object.hash(bits, fractionalDigits, signed);
}

const fixed128x18Type = FixedType(128, 18);
const ufixed128x18Type = FixedType(128, 18, signed: false);

// ── Rational/integer literal type ───────────────────────────────────────────

/// The type of a number literal before it is bound to a concrete type.
///
/// Solidity treats literals like `1`, `0x10` or `2.5` as arbitrary-precision
/// rationals; only when used in context (assignment, arithmetic, a function
/// argument) are they implicitly converted to their *mobile type* — the
/// smallest integer or fixed-point type that can hold the value.
class RationalNumberType extends SolType {
  RationalNumberType(BigInt numerator, BigInt denominator)
    : assert(denominator != BigInt.zero),
      numerator = _reduceNum(numerator, denominator),
      denominator = _reduceDen(numerator, denominator);

  /// Builds an integer-valued rational (denominator 1).
  RationalNumberType.integer(BigInt value)
    : numerator = value,
      denominator = BigInt.one;

  final BigInt numerator;
  final BigInt denominator;

  bool get isInteger => denominator == BigInt.one;
  bool get isNegative => numerator.isNegative;

  static BigInt _gcd(BigInt a, BigInt b) {
    a = a.abs();
    b = b.abs();
    while (b != BigInt.zero) {
      final t = b;
      b = a % b;
      a = t;
    }
    return a == BigInt.zero ? BigInt.one : a;
  }

  static BigInt _reduceNum(BigInt n, BigInt d) {
    final g = _gcd(n, d);
    final sign = d.isNegative ? -BigInt.one : BigInt.one;
    return (n ~/ g) * sign;
  }

  static BigInt _reduceDen(BigInt n, BigInt d) {
    final g = _gcd(n, d);
    return (d ~/ g).abs();
  }

  /// The smallest integer type that can hold this (integer) value, or null if
  /// the value is fractional or does not fit any `intN`/`uintN`.
  IntType? get mobileIntType {
    if (!isInteger) return null;
    final signed = isNegative;
    for (var bits = 8; bits <= 256; bits += 8) {
      final t = IntType(bits, signed: signed);
      if (numerator >= t.min && numerator <= t.max) return t;
    }
    return null;
  }

  @override
  String get abiType =>
      mobileIntType?.abiType ?? (isInteger ? 'int256' : 'fixed128x18');

  @override
  int get abiEncodedSize => 32;

  @override
  bool operator ==(Object other) =>
      other is RationalNumberType &&
      other.numerator == numerator &&
      other.denominator == denominator;

  @override
  int get hashCode => Object.hash(numerator, denominator);

  @override
  String toString() =>
      isInteger ? 'rational $numerator' : 'rational $numerator/$denominator';
}

// ── Boolean ───────────────────────────────────────────────────────────────────

class BoolType extends SolType {
  const BoolType();

  @override
  String get abiType => 'bool';

  @override
  int get abiEncodedSize => 32;
}

const boolType = BoolType();

// ── Address ───────────────────────────────────────────────────────────────────

class AddressType extends SolType {
  const AddressType({this.payable = false});

  final bool payable;

  @override
  String get abiType => 'address';

  @override
  int get abiEncodedSize => 32;

  @override
  bool operator ==(Object other) =>
      other is AddressType && other.payable == payable;

  @override
  int get hashCode => payable.hashCode;
}

const addressType = AddressType();
const addressPayableType = AddressType(payable: true);

// ── Fixed-size bytes ──────────────────────────────────────────────────────────

class BytesNType extends SolType {
  const BytesNType(this.n) : assert(n >= 1 && n <= 32);

  final int n;

  @override
  String get abiType => 'bytes$n';

  @override
  int get abiEncodedSize => 32; // right-padded to 32

  @override
  bool operator ==(Object other) => other is BytesNType && other.n == n;

  @override
  int get hashCode => n.hashCode;
}

// ── Dynamic bytes & string ────────────────────────────────────────────────────

class BytesType extends SolType {
  const BytesType();

  @override
  String get abiType => 'bytes';

  @override
  int get abiEncodedSize => 0; // dynamic
}

class StringType extends SolType {
  const StringType();

  @override
  String get abiType => 'string';

  @override
  int get abiEncodedSize => 0; // dynamic
}

const bytesType = BytesType();
const stringType = StringType();

// ── Array types ───────────────────────────────────────────────────────────────

class ArrayType extends SolType {
  const ArrayType(this.elementType, {this.length});

  final SolType elementType;
  final int? length; // null = dynamic

  bool get isFixed => length != null;

  @override
  String get abiType => '${elementType.abiType}[${length ?? ''}]';

  @override
  int get abiEncodedSize => isFixed && !elementType.isDynamic
      ? length! * elementType.abiEncodedSize
      : 0;

  @override
  bool operator ==(Object other) =>
      other is ArrayType &&
      other.length == length &&
      other.elementType == elementType;

  @override
  int get hashCode => Object.hash(elementType, length);
}

// ── Mapping ───────────────────────────────────────────────────────────────────

class MappingType extends SolType {
  const MappingType(this.keyType, this.valueType);

  final SolType keyType;
  final SolType valueType;

  @override
  String get abiType => 'mapping(${keyType.abiType} => ${valueType.abiType})';

  @override
  int get abiEncodedSize => 0; // mappings are not ABI-encodable directly

  @override
  bool operator ==(Object other) =>
      other is MappingType &&
      other.keyType == keyType &&
      other.valueType == valueType;

  @override
  int get hashCode => Object.hash(keyType, valueType);
}

// ── Tuple / struct ────────────────────────────────────────────────────────────

class TupleType extends SolType {
  const TupleType(this.components);

  final List<SolType> components;

  @override
  String get abiType => '(${components.map((c) => c.abiType).join(',')})';

  @override
  int get abiEncodedSize => components.any((c) => c.isDynamic)
      ? 0
      : components.fold(0, (sum, c) => sum + c.abiEncodedSize);

  @override
  bool operator ==(Object other) {
    if (other is! TupleType || other.components.length != components.length) {
      return false;
    }
    for (var i = 0; i < components.length; i++) {
      if (other.components[i] != components[i]) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hashAll(components);
}

// ── Function type ─────────────────────────────────────────────────────────────

enum StateMutability { pure, view, payable, nonpayable }

class FunctionType extends SolType {
  const FunctionType({
    required this.parameterTypes,
    required this.returnTypes,
    required this.stateMutability,
  });

  final List<SolType> parameterTypes;
  final List<SolType> returnTypes;
  final StateMutability stateMutability;

  @override
  String get abiType => 'function';

  @override
  int get abiEncodedSize => 32; // 24-byte address + 4-byte selector
}

// ── Special ───────────────────────────────────────────────────────────────────

/// The type of `type(X)`.
class TypeType extends SolType {
  const TypeType(this.actualType);

  final SolType actualType;

  @override
  String get abiType => throw UnsupportedError('TypeType has no ABI encoding');

  @override
  int get abiEncodedSize =>
      throw UnsupportedError('TypeType has no ABI encoding');
}

/// Represents an unresolved / error type to allow compilation to continue.
class ErrorType extends SolType {
  const ErrorType();

  @override
  String get abiType => '<error>';

  @override
  int get abiEncodedSize => 32;
}

const errorType = ErrorType();
