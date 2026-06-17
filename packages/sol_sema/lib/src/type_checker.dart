import 'package:sol_ast/sol_ast.dart';
import 'package:sol_support/sol_support.dart';
import 'package:sol_types/sol_types.dart';
import 'scope.dart' as sema;

/// Second pass: annotates every expression node with its [SolType].
///
/// Emits type-mismatch errors into [_diagnostics].
/// Assumes [Resolver] has already run.
class TypeChecker extends AstVisitor {
  TypeChecker(this._diagnostics);

  final DiagnosticCollector _diagnostics;

  // ── Helpers ───────────────────────────────────────────────────────────────

  SolType _typeOf(AstNode node) =>
      node.annotation is SolType ? node.annotation as SolType : errorType;

  void _setType(AstNode node, SolType type) => node.annotation = type;

  void check(SourceFile file) => file.accept(this);

  // ── Top-level ─────────────────────────────────────────────────────────────

  @override
  void visitContractDefinition(ContractDefinition node) {
    for (final m in node.members) m.accept(this);
  }

  @override
  void visitFunctionDefinition(FunctionDefinition node) {
    node.body?.accept(this);
  }

  @override
  void visitModifierDefinition(ModifierDefinition node) {
    node.body.accept(this);
  }

  @override
  void visitStateVariableDeclaration(StateVariableDeclaration node) {
    node.initialValue?.accept(this);
  }

  // ── Statements ────────────────────────────────────────────────────────────

  @override
  void visitBlock(Block node) {
    for (final s in node.statements) s.accept(this);
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
    node.initStatement?.accept(this);
    node.condition?.accept(this);
    node.loopExpression?.accept(this);
    node.body.accept(this);
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
    node.body.accept(this);
  }

  @override
  void visitExpressionStatement(ExpressionStatement node) {
    node.expression.accept(this);
  }

  @override
  void visitVariableDeclarationStatement(VariableDeclarationStatement node) {
    node.initialValue?.accept(this);
    // Type-annotate each declared variable based on its type name.
    for (final decl in node.declarations) {
      if (decl == null) continue;
      final t = _typeFromTypeName(decl.typeName);
      decl.annotation = t;
    }
  }

  // ── Expressions ───────────────────────────────────────────────────────────

  @override
  void visitLiteral(Literal node) {
    switch (node.kind) {
      case LiteralKind.number:
        _setType(node, uint256Type);
      case LiteralKind.bool$:
        _setType(node, boolType);
      case LiteralKind.string || LiteralKind.unicodeString:
        _setType(node, stringType);
      case LiteralKind.hexString:
        _setType(node, bytesType);
    }
  }

  @override
  void visitIdentifier(Identifier node) {
    final sym = node.annotation;
    if (sym is sema.Symbol) {
      _setType(node, sym.type);
    }
    // If annotation is already a SolType, leave it; if null (built-in), leave as-is.
  }

  @override
  void visitBinaryOperation(BinaryOperation node) {
    node.left.accept(this);
    node.right.accept(this);

    final l = _typeOf(node.left);
    final r = _typeOf(node.right);

    // Comparison operators always return bool.
    if (_isComparisonOp(node.operator$)) {
      _setType(node, boolType);
      return;
    }
    // Logical operators: bool × bool → bool.
    if (node.operator$ == '&&' || node.operator$ == '||') {
      _setType(node, boolType);
      return;
    }

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
  void visitUnaryOperation(UnaryOperation node) {
    node.subExpression.accept(this);
    if (node.operator$ == '!') {
      _setType(node, boolType);
    } else {
      _setType(node, _typeOf(node.subExpression));
    }
  }

  @override
  void visitAssignment(Assignment node) {
    node.leftHandSide.accept(this);
    node.rightHandSide.accept(this);
    _setType(node, _typeOf(node.leftHandSide));
  }

  @override
  void visitFunctionCall(FunctionCall node) {
    node.expression.accept(this);
    for (final a in node.arguments) a.accept(this);
    // Type of a call is not yet resolved without full type info — use errorType.
    _setType(node, errorType);
  }

  @override
  void visitMemberAccess(MemberAccess node) {
    node.expression.accept(this);
    // Member type resolution requires full type information; use errorType for now.
    _setType(node, errorType);
  }

  @override
  void visitIndexAccess(IndexAccess node) {
    node.base.accept(this);
    node.index?.accept(this);
    _setType(node, errorType);
  }

  @override
  void visitIndexRangeAccess(IndexRangeAccess node) {
    node.base.accept(this);
    node.start?.accept(this);
    node.end?.accept(this);
    _setType(node, errorType);
  }

  @override
  void visitConditional(Conditional node) {
    node.condition.accept(this);
    node.trueExpression.accept(this);
    node.falseExpression.accept(this);
    final l = _typeOf(node.trueExpression);
    final r = _typeOf(node.falseExpression);
    _setType(node, commonType(l, r) ?? errorType);
  }

  @override
  void visitTupleExpression(TupleExpression node) {
    for (final c in node.components) c?.accept(this);
    _setType(node, errorType);
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  static bool _isComparisonOp(String op) =>
      op == '<' || op == '<=' || op == '>' || op == '>=' ||
      op == '==' || op == '!=';

  /// Approximate type from a type name node. Returns [errorType] if unknown.
  SolType _typeFromTypeName(TypeName? typeName) {
    if (typeName == null) return errorType;
    switch (typeName) {
      case ElementaryTypeName(:final name):
        return _elementaryType(name);
      default:
        return errorType;
    }
  }

  static SolType _elementaryType(String name) {
    if (name == 'bool') return boolType;
    if (name == 'address' || name == 'address payable') return addressType;
    if (name == 'string') return stringType;
    if (name == 'bytes') return bytesType;
    if (name.startsWith('uint')) {
      final bits = name.length > 4 ? int.tryParse(name.substring(4)) : 256;
      return IntType(bits ?? 256, signed: false);
    }
    if (name.startsWith('int')) {
      final bits = name.length > 3 ? int.tryParse(name.substring(3)) : 256;
      return IntType(bits ?? 256);
    }
    if (name.startsWith('bytes') && name.length > 5) {
      final size = int.tryParse(name.substring(5));
      if (size != null) return BytesNType(size);
    }
    return errorType;
  }
}
