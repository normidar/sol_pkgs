import 'package:sol_ast/sol_ast.dart';
import 'package:sol_types/sol_types.dart';

/// Best-effort mapping from an AST [TypeName] to a semantic [SolType].
///
/// Returns [errorType] for type names the front-end does not yet model fully
/// (mappings, user-defined types, function types …). This keeps downstream
/// passes permissive — an unmodelled type compares as compatible with anything
/// — rather than rejecting otherwise-valid programs.
SolType solTypeFromTypeName(TypeName? typeName) {
  if (typeName == null) return errorType;
  switch (typeName) {
    case ElementaryTypeName(:final name):
      return elementarySolType(name);
    case ArrayTypeName(:final baseType, :final length):
      final element = solTypeFromTypeName(baseType);
      return ArrayType(element, length: length is Literal ? _intLit(length) : null);
    case MappingTypeName(:final keyType, :final valueType):
      return MappingType(
          solTypeFromTypeName(keyType), solTypeFromTypeName(valueType));
    default:
      return errorType;
  }
}

/// Maps an elementary type name (`uint256`, `int8`, `bool`, `address`, …) to a
/// [SolType]. Mirrors solc's elementary type grammar, including the bare
/// aliases `uint`/`int` (= 256 bits) and `byte` (= `bytes1`).
SolType elementarySolType(String name) {
  switch (name) {
    case 'bool':
      return boolType;
    case 'address':
      return addressType;
    case 'address payable':
      return addressPayableType;
    case 'string':
      return stringType;
    case 'bytes':
      return bytesType;
    case 'byte':
      return const BytesNType(1);
  }
  if (name.startsWith('uint')) {
    final bits = name.length > 4 ? int.tryParse(name.substring(4)) : 256;
    if (bits != null && bits >= 8 && bits <= 256 && bits % 8 == 0) {
      return IntType(bits, signed: false);
    }
  }
  if (name.startsWith('int')) {
    final bits = name.length > 3 ? int.tryParse(name.substring(3)) : 256;
    if (bits != null && bits >= 8 && bits <= 256 && bits % 8 == 0) {
      return IntType(bits);
    }
  }
  if (name.startsWith('bytes') && name.length > 5) {
    final size = int.tryParse(name.substring(5));
    if (size != null && size >= 1 && size <= 32) return BytesNType(size);
  }
  return errorType;
}

int? _intLit(Literal lit) {
  if (lit.kind != LiteralKind.number) return null;
  final v = lit.value.startsWith('0x')
      ? int.tryParse(lit.value.substring(2), radix: 16)
      : int.tryParse(lit.value);
  return v;
}
