import 'sol_type.dart';

/// Checks whether [from] is implicitly convertible to [to].
///
/// Matches solc's `isImplicitlyConvertibleTo` semantics.
bool isImplicitlyConvertible(SolType from, SolType to) {
  if (from == to) return true;
  if (from is ErrorType || to is ErrorType) return true;

  if (from is IntType && to is IntType) {
    if (from.signed != to.signed) return false;
    return to.bits >= from.bits;
  }

  if (from is AddressType && to is AddressType) {
    // address → address payable only with explicit cast
    if (to.payable && !from.payable) return false;
    return true;
  }

  if (from is BytesNType && to is BytesNType) return to.n >= from.n;

  if (from is ArrayType && to is ArrayType) {
    if (from.length != to.length) return false;
    return isImplicitlyConvertible(from.elementType, to.elementType);
  }

  // Fixed-point: widen bits and fractional digits, same sign.
  if (from is FixedType && to is FixedType) {
    if (from.signed != to.signed) return false;
    return to.bits >= from.bits && to.fractionalDigits >= from.fractionalDigits;
  }

  // A number literal converts to the concrete type it fits in.
  if (from is RationalNumberType) {
    if (to is IntType) {
      if (!from.isInteger) return false;
      if (to.signed != from.isNegative && from.isNegative) return false;
      return from.numerator >= to.min && from.numerator <= to.max;
    }
    if (to is FixedType) return _rationalFitsFixed(from, to);
  }

  return false;
}

/// Whether the rational [r] can be represented exactly in fixed-point type [t].
bool _rationalFitsFixed(RationalNumberType r, FixedType t) {
  if (!t.signed && r.isNegative) return false;
  // Scale the rational by 10^N; it must come out as an integer that fits.
  final scale = BigInt.from(10).pow(t.fractionalDigits);
  final scaled = r.numerator * scale;
  if (scaled % r.denominator != BigInt.zero) return false;
  final value = scaled ~/ r.denominator;
  final limit = t.signed
      ? (BigInt.one << (t.bits - 1))
      : (BigInt.one << t.bits);
  return value.abs() < limit;
}

/// Checks whether [from] is explicitly convertible to [to] (casting).
bool isExplicitlyConvertible(SolType from, SolType to) {
  if (isImplicitlyConvertible(from, to)) return true;
  if (from is ErrorType || to is ErrorType) return true;

  if (from is IntType && to is IntType) return true;
  if (from is IntType && to is AddressType) return from.bits == 160;
  if (from is AddressType && to is IntType) return to.bits == 160;
  if (from is BytesNType && to is IntType) return from.n * 8 == to.bits;
  if (from is IntType && to is BytesNType) return from.bits == to.n * 8;
  if (from is BytesNType && to is BytesNType) return true;
  if (from is AddressType && to is AddressType) return true;

  // Fixed-point may be explicitly cast to any other fixed-point type.
  if (from is FixedType && to is FixedType) return true;

  return false;
}

/// Returns the "common type" for a binary operation, or null if incompatible.
SolType? commonType(SolType a, SolType b) {
  if (a == b) return a;
  if (isImplicitlyConvertible(a, b)) return b;
  if (isImplicitlyConvertible(b, a)) return a;
  return null;
}
