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

  return false;
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

  return false;
}

/// Returns the "common type" for a binary operation, or null if incompatible.
SolType? commonType(SolType a, SolType b) {
  if (a == b) return a;
  if (isImplicitlyConvertible(a, b)) return b;
  if (isImplicitlyConvertible(b, a)) return a;
  return null;
}
