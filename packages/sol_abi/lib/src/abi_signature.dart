import 'dart:typed_data';
import 'package:sol_ast/sol_ast.dart';
import 'package:sol_support/sol_support.dart';

/// Canonical ABI type names, signatures and 4-byte selectors.
///
/// The canonical form is what Solidity hashes to derive function, event and
/// error selectors (e.g. `transfer(address,uint256)`), so this is the single
/// source of truth shared by the ABI-JSON generator and the IR code generator.

/// Solidity type aliases that must be expanded to their canonical ABI form.
const Map<String, String> _elementaryAliases = {
  'uint': 'uint256',
  'int': 'int256',
  'byte': 'bytes1',
  'fixed': 'fixed128x18',
  'ufixed': 'ufixed128x18',
  'address payable': 'address',
};

/// Returns the canonical ABI type string for [typeName]
/// (e.g. `uint256`, `address`, `bytes32`, `uint256[]`, `uint8[3]`).
String abiCanonicalType(TypeName typeName) {
  switch (typeName) {
    case ElementaryTypeName(:final name):
      return _elementaryAliases[name] ?? name;
    case ArrayTypeName(:final baseType, :final length):
      final base = abiCanonicalType(baseType);
      if (length == null) return '$base[]';
      final n = _constLength(length);
      // A non-constant length cannot appear in an ABI type; fall back to
      // dynamic so the signature stays well-formed.
      return n == null ? '$base[]' : '$base[$n]';
    case UserDefinedTypeName(:final nameParts):
      // Best effort without resolved type info: structs become tuples and
      // enums become uint8 only once sema annotations are available.
      return nameParts.last;
    default:
      return 'unknown';
  }
}

/// `name(type,type,…)` for a function.
String functionSignature(FunctionDefinition fn) =>
    '${fn.name}(${_joinParams(fn.parameters)})';

/// `Name(type,type,…)` for an event.
String eventSignature(EventDefinition ev) =>
    '${ev.name}(${_joinParams(ev.parameters)})';

/// `Name(type,type,…)` for a custom error.
String errorSignature(CustomErrorDefinition err) =>
    '${err.name}(${_joinParams(err.parameters)})';

/// The first 4 bytes of `keccak256(signature)`.
Uint8List selectorBytes(String signature) =>
    Uint8List.sublistView(keccak256OfString(signature), 0, 4);

/// The 4-byte selector of [signature] as `0x`-prefixed hex.
String selectorHex(String signature) {
  final sb = StringBuffer('0x');
  for (final b in selectorBytes(signature)) {
    sb.write(b.toRadixString(16).padLeft(2, '0'));
  }
  return sb.toString();
}

/// The `0x`-prefixed 4-byte selector of a function definition.
String functionSelectorHex(FunctionDefinition fn) =>
    selectorHex(functionSignature(fn));

/// The 32-byte event topic (`keccak256(signature)`) as `0x`-prefixed hex.
String eventTopicHex(EventDefinition ev) {
  final sb = StringBuffer('0x');
  for (final b in keccak256OfString(eventSignature(ev))) {
    sb.write(b.toRadixString(16).padLeft(2, '0'));
  }
  return sb.toString();
}

String _joinParams(List<Parameter> params) =>
    params.map((p) => abiCanonicalType(p.typeName)).join(',');

/// Extracts a compile-time constant array length, or null if non-constant.
int? _constLength(Expression expr) {
  if (expr is Literal && expr.kind == LiteralKind.number) {
    final v = expr.value.replaceAll('_', '');
    if (v.startsWith('0x') || v.startsWith('0X')) {
      return int.tryParse(v.substring(2), radix: 16);
    }
    return int.tryParse(v);
  }
  return null;
}
