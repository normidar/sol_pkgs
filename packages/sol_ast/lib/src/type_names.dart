import 'package:sol_support/sol_support.dart';
import 'ast_node.dart';
import 'enums.dart';
import 'visitor.dart';

/// Base class for all type-name nodes.
abstract class TypeName extends AstNode {
  TypeName(super.location);
}

class ElementaryTypeName extends TypeName {
  ElementaryTypeName(super.location, this.name, {this.intWidth = 0});

  final String name;

  /// Non-zero for `intN` / `uintN` (bit width) and `bytesN` (byte count).
  final int intWidth;

  @override
  void accept(AstVisitor visitor) => visitor.visitElementaryTypeName(this);
}

class ArrayTypeName extends TypeName {
  ArrayTypeName(super.location, this.baseType, this.length);

  final TypeName baseType;
  final Expression? length; // null = dynamic array

  @override
  void accept(AstVisitor visitor) => visitor.visitArrayTypeName(this);
}

class MappingTypeName extends TypeName {
  MappingTypeName(super.location, this.keyType, this.valueType);

  final TypeName keyType;
  final TypeName valueType;

  @override
  void accept(AstVisitor visitor) => visitor.visitMappingTypeName(this);
}

class UserDefinedTypeName extends TypeName {
  UserDefinedTypeName(super.location, this.nameParts);

  /// e.g. `['IERC20']` or `['SafeMath', 'add']`.
  final List<String> nameParts;

  String get name => nameParts.join('.');

  @override
  void accept(AstVisitor visitor) => visitor.visitUserDefinedTypeName(this);
}

class FunctionTypeName extends TypeName {
  FunctionTypeName(
    super.location,
    this.parameters,
    this.returnParameters,
    this.stateMutability,
    this.visibility,
  );

  final List<Parameter> parameters;
  final List<Parameter> returnParameters;
  final StateMutability stateMutability;
  final Visibility visibility;

  @override
  void accept(AstVisitor visitor) => visitor.visitFunctionTypeName(this);
}

// ── Parameter & VariableDeclaration ──────────────────────────────────────────
// These live here (not in declarations.dart) to break the circular dependency:
//   FunctionTypeName → Parameter → TypeName → (this file)

class Parameter extends AstNode {
  Parameter(
    super.location,
    this.typeName,
    this.name,
    this.dataLocation, {
    this.indexed = false,
  });

  final TypeName typeName;
  final String? name;
  final DataLocation? dataLocation;

  /// True for `indexed` event parameters.
  final bool indexed;

  @override
  void accept(AstVisitor visitor) => visitor.visitParameter(this);
}

/// A local variable or struct-member declaration.
///
/// Distinct from [Parameter]: parameters belong to function signatures;
/// VariableDeclaration is for `uint256 x` inside bodies and structs.
class VariableDeclaration extends AstNode {
  VariableDeclaration(
    super.location,
    this.typeName,
    this.name,
    this.dataLocation,
  );

  final TypeName typeName;
  final String name;
  final DataLocation? dataLocation;

  @override
  void accept(AstVisitor visitor) => visitor.visitVariableDeclaration(this);
}
