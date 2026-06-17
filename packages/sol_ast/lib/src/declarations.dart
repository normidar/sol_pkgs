import 'package:sol_support/sol_support.dart';
import 'ast_node.dart';
import 'type_names.dart';
import 'statements.dart';
import 'visitor.dart';

// ── Top-level ─────────────────────────────────────────────────────────────────

class SourceFile extends AstNode {
  SourceFile(super.location, this.pragmas, this.imports, this.declarations);

  final List<PragmaDirective> pragmas;
  final List<ImportDirective> imports;
  final List<ContractDefinition> declarations;

  @override
  void accept(AstVisitor visitor) => visitor.visitSourceFile(this);
}

class PragmaDirective extends AstNode {
  PragmaDirective(super.location, this.literals);

  final List<String> literals; // e.g. ['solidity', '^0.8.0']

  @override
  void accept(AstVisitor visitor) => visitor.visitPragmaDirective(this);
}

class ImportDirective extends AstNode {
  ImportDirective(super.location, this.path, this.alias, this.symbolAliases);

  final String path;
  final String? alias;
  final Map<String, String?> symbolAliases; // symbol → local alias

  @override
  void accept(AstVisitor visitor) => visitor.visitImportDirective(this);
}

// ── Contract ──────────────────────────────────────────────────────────────────

enum ContractKind { contract, interface, library }

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
    this.members,
  );

  final ContractKind kind;
  final String name;
  final List<InheritanceSpecifier> baseContracts;
  final List<AstNode> members; // functions, state vars, modifiers, events…

  @override
  void accept(AstVisitor visitor) => visitor.visitContractDefinition(this);
}

// ── Function / constructor ────────────────────────────────────────────────────

class FunctionDefinition extends AstNode {
  FunctionDefinition({
    required SourceLocation location,
    required this.name,
    required this.parameters,
    required this.returnParameters,
    required this.visibility,
    required this.stateMutability,
    required this.isVirtual,
    required this.overrideSpecifier,
    required this.modifiers,
    required this.body,
  }) : super(location);

  final String? name; // null for constructors, fallback, receive
  final List<Parameter> parameters;
  final List<Parameter> returnParameters;
  final Visibility visibility;
  final StateMutability stateMutability;
  final bool isVirtual;
  final List<String> overrideSpecifier;
  final List<ModifierInvocation> modifiers;
  final Block? body; // null for interface functions

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
      super.location, this.name, this.parameters, this.body);

  final String name;
  final List<Parameter> parameters;
  final Block body;

  @override
  void accept(AstVisitor visitor) => visitor.visitModifierDefinition(this);
}

// ── State variable ────────────────────────────────────────────────────────────

class StateVariableDeclaration extends AstNode {
  StateVariableDeclaration(super.location, this.typeName, this.name,
      this.visibility, this.mutability, this.initialValue);

  final TypeName typeName;
  final String name;
  final Visibility visibility;
  final VariableMutability mutability;
  final Expression? initialValue;

  @override
  void accept(AstVisitor visitor) =>
      visitor.visitStateVariableDeclaration(this);
}

enum VariableMutability { mutable, immutable, constant }

// ── Event & Error ─────────────────────────────────────────────────────────────

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

// ── Struct & Enum ─────────────────────────────────────────────────────────────

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

// ── Variable declaration (local / struct member) ──────────────────────────────

class VariableDeclaration extends AstNode {
  VariableDeclaration(
      super.location, this.typeName, this.name, this.dataLocation);

  final TypeName typeName;
  final String name;
  final DataLocation? dataLocation;

  @override
  void accept(AstVisitor visitor) => visitor.visitVariableDeclaration(this);
}
