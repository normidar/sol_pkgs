import 'package:sol_ast/sol_ast.dart';
import 'package:sol_support/sol_support.dart';
import 'package:sol_types/sol_types.dart';
import 'scope.dart';

/// First pass: builds the global symbol table and resolves name references.
///
/// Annotates [Identifier] nodes with the resolved [Symbol] via [AstNode.annotation].
class Resolver extends AstVisitor {
  Resolver(this._diagnostics);

  final DiagnosticCollector _diagnostics;
  Scope _scope = Scope(); // global scope

  void resolve(SourceFile file) {
    // First pass: hoist contract names into global scope.
    for (final contract in file.declarations) {
      _scope.declare(Symbol(
        name: contract.name,
        type: const ErrorType(), // refined later by type checker
        kind: SymbolKind.contract,
      ));
    }
    file.accept(this);
  }

  @override
  void visitContractDefinition(ContractDefinition node) {
    final saved = _scope;
    _scope = Scope(parent: _scope);

    // Hoist all member names first (forward refs within the contract).
    for (final member in node.members) {
      switch (member) {
        case FunctionDefinition fn when fn.name != null:
          _scope.declare(Symbol(
            name: fn.name!,
            type: const ErrorType(),
            kind: SymbolKind.function,
          ));
        case StateVariableDeclaration sv:
          _scope.declare(Symbol(
            name: sv.name,
            type: const ErrorType(),
            kind: SymbolKind.stateVariable,
          ));
        case EventDefinition ev:
          _scope.declare(Symbol(
            name: ev.name,
            type: const ErrorType(),
            kind: SymbolKind.event,
          ));
        default:
          break;
      }
    }

    for (final member in node.members) {
      member.accept(this);
    }

    _scope = saved;
  }

  @override
  void visitFunctionDefinition(FunctionDefinition node) {
    final saved = _scope;
    _scope = Scope(parent: _scope);

    for (final p in node.parameters) {
      _scope.declare(Symbol(
        name: p.name ?? '',
        type: const ErrorType(),
        kind: SymbolKind.parameter,
      ));
    }

    node.body?.accept(this);
    _scope = saved;
  }

  @override
  void visitBlock(Block node) {
    final saved = _scope;
    _scope = Scope(parent: _scope);
    for (final s in node.statements) s.accept(this);
    _scope = saved;
  }

  @override
  void visitIdentifier(Identifier node) {
    final sym = _scope.lookup(node.name);
    if (sym != null) {
      node.annotation = sym;
    } else {
      _diagnostics.error(
        'Undeclared identifier "${node.name}"',
        location: node.location,
      );
    }
  }

  @override
  void visitVariableDeclarationStatement(VariableDeclarationStatement node) {
    node.initialValue?.accept(this);
    for (final decl in node.declarations) {
      if (decl == null) continue;
      _scope.declare(Symbol(
        name: decl.name,
        type: const ErrorType(),
        kind: SymbolKind.localVariable,
      ));
    }
  }
}
