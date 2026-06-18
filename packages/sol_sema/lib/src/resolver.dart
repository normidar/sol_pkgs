import 'package:sol_ast/sol_ast.dart';
import 'package:sol_support/sol_support.dart';
import 'package:sol_types/sol_types.dart';
import 'scope.dart';
import 'type_resolution.dart';

/// First pass: builds the global symbol table and resolves name references.
///
/// Annotates [Identifier] nodes with the resolved [Symbol] via [AstNode.annotation].
class Resolver extends AstVisitor {
  Resolver(this._diagnostics);

  final DiagnosticCollector _diagnostics;
  Scope _scope = Scope(); // global scope

  void resolve(SourceFile file) {
    // Hoist all top-level contract names so they can reference each other.
    for (final contract in file.declarations) {
      _scope.declare(
        Symbol(
          name: contract.name,
          type: const ErrorType(),
          kind: SymbolKind.contract,
        ),
      );
    }
    file.accept(this);
  }

  @override
  void visitContractDefinition(ContractDefinition node) {
    final saved = _scope;
    _scope = Scope(parent: _scope);

    // Hoist all member names first so forward references within the contract work.
    for (final member in node.members) {
      switch (member) {
        case FunctionDefinition fn when fn.name != null:
          _scope.declare(
            Symbol(
              name: fn.name!,
              type: _functionReturnType(fn),
              kind: SymbolKind.function,
            ),
          );
        case StateVariableDeclaration sv:
          _scope.declare(
            Symbol(
              name: sv.name,
              type: solTypeFromTypeName(sv.typeName),
              kind: SymbolKind.stateVariable,
            ),
          );
        case EventDefinition ev:
          _scope.declare(
            Symbol(
              name: ev.name,
              type: const ErrorType(),
              kind: SymbolKind.event,
            ),
          );
        case CustomErrorDefinition err:
          _scope.declare(
            Symbol(
              name: err.name,
              type: const ErrorType(),
              kind: SymbolKind.error,
            ),
          );
        case StructDefinition s:
          _scope.declare(
            Symbol(
              name: s.name,
              type: const ErrorType(),
              kind: SymbolKind.struct,
            ),
          );
        case EnumDefinition e:
          _scope.declare(
            Symbol(
              name: e.name,
              type: const ErrorType(),
              kind: SymbolKind.enum$,
            ),
          );
        case ModifierDefinition m:
          _scope.declare(
            Symbol(
              name: m.name,
              type: const ErrorType(),
              kind: SymbolKind.modifier,
            ),
          );
        case UserDefinedValueTypeDefinition uvt:
          _scope.declare(
            Symbol(
              name: uvt.name,
              type: const ErrorType(),
              kind: SymbolKind.contract, // treated as a type alias
            ),
          );
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
      if (p.name != null && p.name!.isNotEmpty) {
        _scope.declare(
          Symbol(
            name: p.name!,
            type: solTypeFromTypeName(p.typeName),
            kind: SymbolKind.parameter,
          ),
        );
      }
    }
    for (final p in node.returnParameters) {
      if (p.name != null && p.name!.isNotEmpty) {
        _scope.declare(
          Symbol(
            name: p.name!,
            type: solTypeFromTypeName(p.typeName),
            kind: SymbolKind.localVariable,
          ),
        );
      }
    }

    node.body?.accept(this);
    _scope = saved;
  }

  @override
  void visitModifierDefinition(ModifierDefinition node) {
    final saved = _scope;
    _scope = Scope(parent: _scope);

    for (final p in node.parameters) {
      if (p.name != null && p.name!.isNotEmpty) {
        _scope.declare(
          Symbol(
            name: p.name!,
            type: solTypeFromTypeName(p.typeName),
            kind: SymbolKind.parameter,
          ),
        );
      }
    }

    node.body.accept(this);
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
  void visitIfStatement(IfStatement node) {
    node.condition.accept(this);
    node.trueBody.accept(this);
    node.falseBody?.accept(this);
  }

  @override
  void visitWhileStatement(WhileStatement node) {
    node.condition.accept(this);
    node.body.accept(this);
  }

  @override
  void visitDoWhileStatement(DoWhileStatement node) {
    node.body.accept(this);
    node.condition.accept(this);
  }

  @override
  void visitForStatement(ForStatement node) {
    final saved = _scope;
    _scope = Scope(parent: _scope);
    node.initStatement?.accept(this);
    node.condition?.accept(this);
    node.loopExpression?.accept(this);
    node.body.accept(this);
    _scope = saved;
  }

  @override
  void visitReturnStatement(ReturnStatement node) {
    node.expression?.accept(this);
  }

  @override
  void visitRevertStatement(RevertStatement node) {
    node.expression.accept(this);
  }

  @override
  void visitEmitStatement(EmitStatement node) {
    node.call.accept(this);
  }

  @override
  void visitUncheckedStatement(UncheckedStatement node) {
    node.body.accept(this);
  }

  @override
  void visitTryStatement(TryStatement node) {
    node.externalCall.accept(this);
    for (final c in node.clauses) c.accept(this);
  }

  @override
  void visitCatchClause(CatchClause node) {
    final saved = _scope;
    _scope = Scope(parent: _scope);
    for (final p in node.parameters) {
      if (p.name != null && p.name!.isNotEmpty) {
        _scope.declare(
          Symbol(
            name: p.name!,
            type: solTypeFromTypeName(p.typeName),
            kind: SymbolKind.parameter,
          ),
        );
      }
    }
    node.body.accept(this);
    _scope = saved;
  }

  @override
  void visitExpressionStatement(ExpressionStatement node) {
    node.expression.accept(this);
  }

  @override
  void visitVariableDeclarationStatement(VariableDeclarationStatement node) {
    node.initialValue?.accept(this);
    for (final decl in node.declarations) {
      if (decl == null) continue;
      _scope.declare(
        Symbol(
          name: decl.name,
          type: solTypeFromTypeName(decl.typeName),
          kind: SymbolKind.localVariable,
        ),
      );
    }
  }

  @override
  void visitIdentifier(Identifier node) {
    // Suppress false positives for well-known Solidity built-ins.
    if (_isBuiltinName(node.name)) return;

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
  void visitBinaryOperation(BinaryOperation node) {
    node.left.accept(this);
    node.right.accept(this);
  }

  @override
  void visitUnaryOperation(UnaryOperation node) {
    node.subExpression.accept(this);
  }

  @override
  void visitAssignment(Assignment node) {
    node.leftHandSide.accept(this);
    node.rightHandSide.accept(this);
  }

  @override
  void visitFunctionCall(FunctionCall node) {
    node.expression.accept(this);
    for (final a in node.arguments) a.accept(this);
  }

  @override
  void visitMemberAccess(MemberAccess node) {
    node.expression.accept(this);
    // The member name is resolved against the expression's type in TypeChecker;
    // do not look it up in the scope here.
  }

  @override
  void visitIndexAccess(IndexAccess node) {
    node.base.accept(this);
    node.index?.accept(this);
  }

  @override
  void visitIndexRangeAccess(IndexRangeAccess node) {
    node.base.accept(this);
    node.start?.accept(this);
    node.end?.accept(this);
  }

  @override
  void visitConditional(Conditional node) {
    node.condition.accept(this);
    node.trueExpression.accept(this);
    node.falseExpression.accept(this);
  }

  @override
  void visitTupleExpression(TupleExpression node) {
    for (final c in node.components) {
      c?.accept(this);
    }
  }

  /// Computes the return type of a function from its return parameters.
  static SolType _functionReturnType(FunctionDefinition fn) {
    if (fn.returnParameters.isEmpty) return const ErrorType();
    if (fn.returnParameters.length == 1) {
      return solTypeFromTypeName(fn.returnParameters.first.typeName);
    }
    return TupleType(
      fn.returnParameters.map((p) => solTypeFromTypeName(p.typeName)).toList(),
    );
  }

  /// Names that are globally available in Solidity without declaration.
  static bool _isBuiltinName(String name) => _builtins.contains(name);

  static const _builtins = {
    // Special variables
    'this', 'super',
    // Global objects
    'msg', 'block', 'tx', 'abi',
    // Built-in functions
    'require', 'revert', 'assert',
    'keccak256', 'sha256', 'ripemd160', 'ecrecover',
    'addmod', 'mulmod',
    'selfdestruct', 'suicide',
    'blockhash', 'gasleft',
    // Built-in types used as functions / constructors
    'type',
    // Address members are accessed via MemberAccess, not Identifier
    // Numeric limits etc.
    'now',
  };
}
