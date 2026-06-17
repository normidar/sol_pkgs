import 'package:sol_support/sol_support.dart';
import 'ast_node.dart';
import 'type_names.dart';
import 'visitor.dart';

abstract class Statement extends AstNode {
  Statement(super.location);
}

class Block extends Statement {
  Block(super.location, this.statements);

  final List<Statement> statements;

  @override
  void accept(AstVisitor visitor) => visitor.visitBlock(this);
}

class ReturnStatement extends Statement {
  ReturnStatement(super.location, this.expression);

  final Expression? expression;

  @override
  void accept(AstVisitor visitor) => visitor.visitReturnStatement(this);
}

class ExpressionStatement extends Statement {
  ExpressionStatement(super.location, this.expression);

  final Expression expression;

  @override
  void accept(AstVisitor visitor) => visitor.visitExpressionStatement(this);
}

class VariableDeclarationStatement extends Statement {
  VariableDeclarationStatement(
      super.location, this.declarations, this.initialValue);

  final List<VariableDeclaration?> declarations;
  final Expression? initialValue;

  @override
  void accept(AstVisitor visitor) =>
      visitor.visitVariableDeclarationStatement(this);
}

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
  ForStatement(super.location, this.initExpression, this.condition,
      this.loopExpression, this.body);

  final Statement? initExpression;
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

class AssemblyStatement extends Statement {
  AssemblyStatement(super.location, this.dialect, this.rawYul);

  final String? dialect;
  final String rawYul;

  @override
  void accept(AstVisitor visitor) => visitor.visitAssemblyStatement(this);
}

// forward ref
class VariableDeclaration extends AstNode {
  VariableDeclaration(
      super.location, this.typeName, this.name, this.dataLocation);

  final TypeName typeName;
  final String name;
  final DataLocation? dataLocation;

  @override
  void accept(AstVisitor visitor) {}
}
