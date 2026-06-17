import 'package:sol_support/sol_support.dart';
import 'ast_node.dart';
import 'enums.dart';
import 'statements.dart';
import 'type_names.dart';
import 'visitor.dart';

// ── Source file ───────────────────────────────────────────────────────────────

class SourceFile extends AstNode {
  SourceFile(super.location, this.pragmas, this.imports, this.declarations);

  final List<PragmaDirective> pragmas;
  final List<ImportDirective> imports;
  final List<ContractDefinition> declarations;

  @override
  void accept(AstVisitor visitor) => visitor.visitSourceFile(this);
}

// ── Pragmas & imports ─────────────────────────────────────────────────────────

class PragmaDirective extends AstNode {
  PragmaDirective(super.location, this.literals);

  /// e.g. `['solidity', '^0.8.0']`
  final List<String> literals;

  @override
  void accept(AstVisitor visitor) => visitor.visitPragmaDirective(this);
}

class ImportDirective extends AstNode {
  ImportDirective(
    super.location,
    this.path,
    this.alias,
    this.symbolAliases,
  );

  final String path;
  final String? alias;

  /// symbol → local alias (null = keep original name).
  final Map<String, String?> symbolAliases;

  @override
  void accept(AstVisitor visitor) => visitor.visitImportDirective(this);
}

// ── Contract ──────────────────────────────────────────────────────────────────

class InheritanceSpecifier extends AstNode {
  InheritanceSpecifier(super.location, this.name, this.arguments);

  final String name;
  final List<Expression> arguments;

  @override
  void accept(AstVisitor visitor) => visitor.visitInheritanceSpecifier(this);
}

class ContractDefinition extends AstNode {
  ContractDefinition(
    super.location,
    this.kind,
    this.name,
    this.baseContracts,
    this.members, {
    this.isAbstract = false,
  });

  final ContractKind kind;
  final String name;
  final List<InheritanceSpecifier> baseContracts;
  final List<AstNode> members;
  final bool isAbstract;

  @override
  void accept(AstVisitor visitor) => visitor.visitContractDefinition(this);
}

// ── Function ──────────────────────────────────────────────────────────────────

enum FunctionKind { function, constructor, fallback, receive }

class FunctionDefinition extends AstNode {
  FunctionDefinition({
    required SourceLocation location,
    required this.kind,
    required this.name,
    required this.parameters,
    required this.returnParameters,
    required this.visibility,
    required this.stateMutability,
    required this.isVirtual,
    required this.overrideSpecifier,
    required this.modifiers,
    this.body,
  }) : super(location);

  final FunctionKind kind;

  /// `null` for constructor / fallback / receive.
  final String? name;
  final List<Parameter> parameters;
  final List<Parameter> returnParameters;
  final Visibility visibility;
  final StateMutability stateMutability;
  final bool isVirtual;

  /// Contracts listed in `override(A, B)`, or `[]` for bare `override`.
  final List<String> overrideSpecifier;
  final List<ModifierInvocation> modifiers;

  /// `null` for interface functions and abstract functions.
  final Block? body;

  @override
  void accept(AstVisitor visitor) => visitor.visitFunctionDefinition(this);
}

class ModifierInvocation extends AstNode {
  ModifierInvocation(super.location, this.name, this.arguments);

  final String name;
  final List<Expression> arguments;

  @override
  void accept(AstVisitor visitor) => visitor.visitModifierInvocation(this);
}

class ModifierDefinition extends AstNode {
  ModifierDefinition(
    super.location,
    this.name,
    this.parameters,
    this.body, {
    this.isVirtual = false,
    this.overrideSpecifier = const [],
  });

  final String name;
  final List<Parameter> parameters;
  final Block body;
  final bool isVirtual;
  final List<String> overrideSpecifier;

  @override
  void accept(AstVisitor visitor) => visitor.visitModifierDefinition(this);
}

// ── State variables ───────────────────────────────────────────────────────────

class StateVariableDeclaration extends AstNode {
  StateVariableDeclaration(
    super.location,
    this.typeName,
    this.name,
    this.visibility,
    this.mutability,
    this.initialValue,
  );

  final TypeName typeName;
  final String name;
  final Visibility visibility;
  final VariableMutability mutability;
  final Expression? initialValue;

  @override
  void accept(AstVisitor visitor) =>
      visitor.visitStateVariableDeclaration(this);
}

// ── Events & errors ───────────────────────────────────────────────────────────

class EventDefinition extends AstNode {
  EventDefinition(super.location, this.name, this.parameters, this.anonymous);

  final String name;
  final List<Parameter> parameters;
  final bool anonymous;

  @override
  void accept(AstVisitor visitor) => visitor.visitEventDefinition(this);
}

class CustomErrorDefinition extends AstNode {
  CustomErrorDefinition(super.location, this.name, this.parameters);

  final String name;
  final List<Parameter> parameters;

  @override
  void accept(AstVisitor visitor) => visitor.visitCustomErrorDefinition(this);
}

// ── Structs & enums ───────────────────────────────────────────────────────────

class StructDefinition extends AstNode {
  StructDefinition(super.location, this.name, this.members);

  final String name;
  final List<VariableDeclaration> members;

  @override
  void accept(AstVisitor visitor) => visitor.visitStructDefinition(this);
}

class EnumDefinition extends AstNode {
  EnumDefinition(super.location, this.name, this.values);

  final String name;
  final List<String> values;

  @override
  void accept(AstVisitor visitor) => visitor.visitEnumDefinition(this);
}

// ── Using directive ───────────────────────────────────────────────────────────

class UsingDirective extends AstNode {
  UsingDirective(super.location, this.libraryName, this.typeName);

  final String libraryName;

  /// `null` = `using X for *`
  final TypeName? typeName;

  @override
  void accept(AstVisitor visitor) => visitor.visitUsingDirective(this);
}

// ── Type definition (user-defined value type) ─────────────────────────────────

class UserDefinedValueTypeDefinition extends AstNode {
  UserDefinedValueTypeDefinition(super.location, this.name, this.underlyingType);

  final String name;
  final TypeName underlyingType;

  @override
  void accept(AstVisitor visitor) =>
      visitor.visitUserDefinedValueTypeDefinition(this);
}
