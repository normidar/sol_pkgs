import 'ast_node.dart';
import 'enums.dart';
import 'type_names.dart';
import 'visitor.dart';

// ── Literals ──────────────────────────────────────────────────────────────────

class Literal extends Expression {
  Literal(super.location, this.kind, this.value, this.subdenomination);

  final LiteralKind kind;
  final String value;
  final String? subdenomination; // 'ether', 'gwei', 'days', …

  @override
  void accept(AstVisitor visitor) => visitor.visitLiteral(this);
}

// ── Identifier & member access ────────────────────────────────────────────────

class Identifier extends Expression {
  Identifier(super.location, this.name);

  final String name;

  @override
  void accept(AstVisitor visitor) => visitor.visitIdentifier(this);
}

class MemberAccess extends Expression {
  MemberAccess(super.location, this.expression, this.memberName);

  final Expression expression;
  final String memberName;

  @override
  void accept(AstVisitor visitor) => visitor.visitMemberAccess(this);
}

class IndexAccess extends Expression {
  IndexAccess(super.location, this.base, this.index);

  final Expression base;
  final Expression? index;

  @override
  void accept(AstVisitor visitor) => visitor.visitIndexAccess(this);
}

class IndexRangeAccess extends Expression {
  IndexRangeAccess(super.location, this.base, this.start, this.end);

  final Expression base;
  final Expression? start;
  final Expression? end;

  @override
  void accept(AstVisitor visitor) => visitor.visitIndexRangeAccess(this);
}

// ── Calls & new ───────────────────────────────────────────────────────────────

class FunctionCall extends Expression {
  FunctionCall(
    super.location,
    this.expression,
    this.arguments,
    this.argumentNames,
  );

  final Expression expression;
  final List<Expression> arguments;

  /// Parallel to [arguments]; non-null entry = named argument.
  final List<String?> argumentNames;

  @override
  void accept(AstVisitor visitor) => visitor.visitFunctionCall(this);
}

/// `f{value: v, gas: g}(args)` — call options.
class FunctionCallOptions extends Expression {
  FunctionCallOptions(super.location, this.expression, this.options);

  final Expression expression;
  final Map<String, Expression> options;

  @override
  void accept(AstVisitor visitor) => visitor.visitFunctionCallOptions(this);
}

class NewExpression extends Expression {
  NewExpression(super.location, this.typeName);

  final TypeName typeName;

  @override
  void accept(AstVisitor visitor) => visitor.visitNewExpression(this);
}

// ── Operators ─────────────────────────────────────────────────────────────────

class UnaryOperation extends Expression {
  UnaryOperation(
    super.location,
    this.operator$,
    this.subExpression,
    this.prefix,
  );

  final String operator$;
  final Expression subExpression;
  final bool prefix;

  @override
  void accept(AstVisitor visitor) => visitor.visitUnaryOperation(this);
}

class BinaryOperation extends Expression {
  BinaryOperation(super.location, this.operator$, this.left, this.right);

  final String operator$;
  final Expression left;
  final Expression right;

  @override
  void accept(AstVisitor visitor) => visitor.visitBinaryOperation(this);
}

class Assignment extends Expression {
  Assignment(
    super.location,
    this.operator$,
    this.leftHandSide,
    this.rightHandSide,
  );

  final String operator$;
  final Expression leftHandSide;
  final Expression rightHandSide;

  @override
  void accept(AstVisitor visitor) => visitor.visitAssignment(this);
}

class Conditional extends Expression {
  Conditional(
    super.location,
    this.condition,
    this.trueExpression,
    this.falseExpression,
  );

  final Expression condition;
  final Expression trueExpression;
  final Expression falseExpression;

  @override
  void accept(AstVisitor visitor) => visitor.visitConditional(this);
}

// ── Type conversions & special forms ─────────────────────────────────────────

class TypeConversion extends Expression {
  TypeConversion(super.location, this.typeName, this.expression);

  final TypeName typeName;
  final Expression expression;

  @override
  void accept(AstVisitor visitor) => visitor.visitTypeConversion(this);
}

class TupleExpression extends Expression {
  TupleExpression(super.location, this.components, this.isArray);

  final List<Expression?> components;
  final bool isArray;

  @override
  void accept(AstVisitor visitor) => visitor.visitTupleExpression(this);
}

/// `delete x`
class DeleteExpression extends Expression {
  DeleteExpression(super.location, this.expression);

  final Expression expression;

  @override
  void accept(AstVisitor visitor) => visitor.visitDeleteExpression(this);
}

/// `type(T)`, `type(T).min`, `type(T).max` — resolved as MemberAccess later.
class TypeExpression extends Expression {
  TypeExpression(super.location, this.typeName);

  final TypeName typeName;

  @override
  void accept(AstVisitor visitor) => visitor.visitTypeExpression(this);
}
