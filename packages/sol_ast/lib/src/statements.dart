import 'ast_node.dart';
import 'type_names.dart';
import 'visitor.dart';

// ── Block ─────────────────────────────────────────────────────────────────────

class Block extends Statement {
  Block(super.location, this.statements);

  final List<Statement> statements;

  @override
  void accept(AstVisitor visitor) => visitor.visitBlock(this);
}

// ── Control flow ──────────────────────────────────────────────────────────────

class IfStatement extends Statement {
  IfStatement(super.location, this.condition, this.trueBody, this.falseBody);

  final Expression condition;
  final Statement trueBody;
  final Statement? falseBody;

  @override
  void accept(AstVisitor visitor) => visitor.visitIfStatement(this);
}

class WhileStatement extends Statement {
  WhileStatement(super.location, this.condition, this.body);

  final Expression condition;
  final Statement body;

  @override
  void accept(AstVisitor visitor) => visitor.visitWhileStatement(this);
}

class ForStatement extends Statement {
  ForStatement(
    super.location,
    this.initStatement,
    this.condition,
    this.loopExpression,
    this.body,
  );

  final Statement? initStatement;
  final Expression? condition;
  final ExpressionStatement? loopExpression;
  final Statement body;

  @override
  void accept(AstVisitor visitor) => visitor.visitForStatement(this);
}

class DoWhileStatement extends Statement {
  DoWhileStatement(super.location, this.body, this.condition);

  final Statement body;
  final Expression condition;

  @override
  void accept(AstVisitor visitor) => visitor.visitDoWhileStatement(this);
}

class BreakStatement extends Statement {
  BreakStatement(super.location);

  @override
  void accept(AstVisitor visitor) => visitor.visitBreakStatement(this);
}

class ContinueStatement extends Statement {
  ContinueStatement(super.location);

  @override
  void accept(AstVisitor visitor) => visitor.visitContinueStatement(this);
}

class ReturnStatement extends Statement {
  ReturnStatement(super.location, this.expression);

  final Expression? expression;

  @override
  void accept(AstVisitor visitor) => visitor.visitReturnStatement(this);
}

// ── Expression & variable statements ─────────────────────────────────────────

class ExpressionStatement extends Statement {
  ExpressionStatement(super.location, this.expression);

  final Expression expression;

  @override
  void accept(AstVisitor visitor) => visitor.visitExpressionStatement(this);
}

class VariableDeclarationStatement extends Statement {
  VariableDeclarationStatement(
    super.location,
    this.declarations,
    this.initialValue,
  );

  /// Entries can be null for tuple slots that are skipped: `(a,, b) = f()`.
  final List<VariableDeclaration?> declarations;
  final Expression? initialValue;

  @override
  void accept(AstVisitor visitor) =>
      visitor.visitVariableDeclarationStatement(this);
}

// ── Revert / emit ─────────────────────────────────────────────────────────────

class RevertStatement extends Statement {
  RevertStatement(super.location, this.expression);

  final Expression expression;

  @override
  void accept(AstVisitor visitor) => visitor.visitRevertStatement(this);
}

class EmitStatement extends Statement {
  EmitStatement(super.location, this.call);

  final Expression call;

  @override
  void accept(AstVisitor visitor) => visitor.visitEmitStatement(this);
}

// ── Special blocks ────────────────────────────────────────────────────────────

class UncheckedStatement extends Statement {
  UncheckedStatement(super.location, this.body);

  final Block body;

  @override
  void accept(AstVisitor visitor) => visitor.visitUncheckedStatement(this);
}

class AssemblyStatement extends Statement {
  AssemblyStatement(super.location, this.dialect, this.rawYul);

  final String? dialect;
  final String rawYul;

  @override
  void accept(AstVisitor visitor) => visitor.visitAssemblyStatement(this);
}

// ── Try/catch ─────────────────────────────────────────────────────────────────

class TryStatement extends Statement {
  TryStatement(super.location, this.externalCall, this.clauses);

  final Expression externalCall;
  final List<CatchClause> clauses;

  @override
  void accept(AstVisitor visitor) => visitor.visitTryStatement(this);
}

class CatchClause extends AstNode {
  CatchClause(super.location, this.errorName, this.parameters, this.body);

  /// `null` = bare `catch { }` or `catch (bytes memory reason) { }`.
  final String? errorName;
  final List<Parameter> parameters;
  final Block body;

  @override
  void accept(AstVisitor visitor) => visitor.visitCatchClause(this);
}
