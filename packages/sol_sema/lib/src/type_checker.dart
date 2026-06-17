import 'package:sol_ast/sol_ast.dart';
import 'package:sol_support/sol_support.dart';
import 'package:sol_types/sol_types.dart';

/// Second pass: annotates every expression node with its [SolType].
///
/// Emits type-mismatch errors into [_diagnostics].
/// Assumes [Resolver] has already run.
class TypeChecker extends AstVisitor {
  TypeChecker(this._diagnostics);

  final DiagnosticCollector _diagnostics;

  // ── Type resolution helpers ───────────────────────────────────────────────

  SolType _typeOf(AstNode node) =>
      node.annotation is SolType ? node.annotation as SolType : errorType;

  void _setType(AstNode node, SolType type) => node.annotation = type;

  // ── Expressions ───────────────────────────────────────────────────────────

  @override
  void visitLiteral(Literal node) {
    switch (node.kind) {
      case LiteralKind.number:
        _setType(node, uint256Type); // simplified; proper rational needed
      case LiteralKind.bool$:
        _setType(node, boolType);
      case LiteralKind.string || LiteralKind.unicodeString:
        _setType(node, stringType);
      case LiteralKind.hexString:
        _setType(node, bytesType);
    }
  }

  @override
  void visitBinaryOperation(BinaryOperation node) {
    node.left.accept(this);
    node.right.accept(this);

    final l = _typeOf(node.left);
    final r = _typeOf(node.right);
    final common = commonType(l, r);

    if (common == null) {
      _diagnostics.error(
        'Operator "${node.operator$}" not compatible with types '
        '"${l.abiType}" and "${r.abiType}"',
        location: node.location,
      );
      _setType(node, errorType);
    } else {
      _setType(node, common);
    }
  }

  @override
  void visitReturnStatement(ReturnStatement node) {
    node.expression?.accept(this);
  }

  @override
  void visitFunctionDefinition(FunctionDefinition node) {
    node.body?.accept(this);
  }

  @override
  void visitBlock(Block node) {
    for (final s in node.statements) s.accept(this);
  }

  @override
  void visitExpressionStatement(ExpressionStatement node) =>
      node.expression.accept(this);

  @override
  void visitContractDefinition(ContractDefinition node) {
    for (final m in node.members) m.accept(this);
  }
}
