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
}

const uint8Type = IntType(8, signed: false);
const uint256Type = IntType(256, signed: false);
const int256Type = IntType(256, signed: true);

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
