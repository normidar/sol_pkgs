import 'package:sol_ast/sol_ast.dart';
import 'package:sol_support/sol_support.dart';
import 'package:sol_types/sol_types.dart';
import 'scope.dart' as sema;
import 'type_resolution.dart';

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
      decl.annotation = solTypeFromTypeName(decl.typeName);
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

    // Shifts: the result has the (left) value operand's type; the shift amount
    // may be any unsigned integer, so no common type is required.
    if (node.operator$ == '<<' ||
        node.operator$ == '>>' ||
        node.operator$ == '>>>') {
      _setType(node, l);
      return;
    }

    // A number literal adapts to the other operand's integer type — `x - 1`
    // with `int256 x` is valid even though the literal is nominally uint256.
    final common = _isNumberLiteral(node.left) && r is IntType
        ? r
        : _isNumberLiteral(node.right) && l is IntType
            ? l
            : commonType(l, r);
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

  static bool _isNumberLiteral(Expression e) =>
      e is Literal && e.kind == LiteralKind.number;

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
    // Built-in global members (msg.sender, block.timestamp, …) carry useful
    // value types; everything else needs full member resolution (not yet done).
    _setType(node, _globalMemberType(node) ?? errorType);
  }

  /// Types of the common `msg`/`block`/`tx` members, or null if unknown.
  static SolType? _globalMemberType(MemberAccess node) {
    final base = node.expression;
    if (base is! Identifier) return null;
    switch ('${base.name}.${node.memberName}') {
      case 'msg.sender':
      case 'tx.origin':
      case 'block.coinbase':
        return addressType;
      case 'msg.value':
      case 'block.timestamp':
      case 'block.number':
      case 'block.gaslimit':
      case 'block.chainid':
      case 'block.basefee':
      case 'block.difficulty':
      case 'block.prevrandao':
      case 'tx.gasprice':
        return uint256Type;
      default:
        return null;
    }
  }

  @override
  void visitIndexAccess(IndexAccess node) {
    node.base.accept(this);
    node.index?.accept(this);
    final baseT = _typeOf(node.base);
    if (baseT is MappingType) {
      _setType(node, baseT.valueType);
    } else if (baseT is ArrayType) {
      _setType(node, baseT.elementType);
    } else {
      _setType(node, errorType);
    }
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
    if (node.components.length == 1 && node.components.first != null) {
      // Parenthesised expression `(e)` — propagate the inner type.
      _setType(node, _typeOf(node.components.first!));
    } else {
      _setType(node, errorType);
    }
  }

  @override
  void visitTypeConversion(TypeConversion node) {
    node.expression.accept(this);
    // An explicit cast `T(x)` has the static type of the target type `T`.
    _setType(node, solTypeFromTypeName(node.typeName));
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  static bool _isComparisonOp(String op) =>
      op == '<' || op == '<=' || op == '>' || op == '>=' ||
      op == '==' || op == '!=';
}
