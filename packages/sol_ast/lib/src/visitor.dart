import 'declarations.dart';
import 'expressions.dart';
import 'statements.dart';
import 'type_names.dart';

/// Double-dispatch visitor.  Override only the nodes you care about.
abstract class AstVisitor {
  // ── Declarations ──────────────────────────────────────────────────────────
  void visitSourceFile(SourceFile node) => _visitChildren(node);
  void visitPragmaDirective(PragmaDirective node) {}
  void visitImportDirective(ImportDirective node) {}
  void visitContractDefinition(ContractDefinition node) =>
      _visitChildren(node);
  void visitInheritanceSpecifier(InheritanceSpecifier node) {}
  void visitFunctionDefinition(FunctionDefinition node) =>
      _visitChildren(node);
  void visitModifierDefinition(ModifierDefinition node) =>
      _visitChildren(node);
  void visitModifierInvocation(ModifierInvocation node) {}
  void visitStateVariableDeclaration(StateVariableDeclaration node) {}
  void visitEventDefinition(EventDefinition node) {}
  void visitCustomErrorDefinition(CustomErrorDefinition node) {}
  void visitStructDefinition(StructDefinition node) {}
  void visitEnumDefinition(EnumDefinition node) {}
  void visitVariableDeclaration(VariableDeclaration node) {}
  void visitParameter(Parameter node) {}

  // ── Type names ─────────────────────────────────────────────────────────────
  void visitElementaryTypeName(ElementaryTypeName node) {}
  void visitArrayTypeName(ArrayTypeName node) {}
  void visitMappingTypeName(MappingTypeName node) {}
  void visitUserDefinedTypeName(UserDefinedTypeName node) {}
  void visitFunctionTypeName(FunctionTypeName node) {}

  // ── Statements ─────────────────────────────────────────────────────────────
  void visitBlock(Block node) {
    for (final s in node.statements) s.accept(this);
  }

  void visitReturnStatement(ReturnStatement node) =>
      node.expression?.accept(this);
  void visitExpressionStatement(ExpressionStatement node) =>
      node.expression.accept(this);
  void visitVariableDeclarationStatement(
          VariableDeclarationStatement node) =>
      node.initialValue?.accept(this);
  void visitIfStatement(IfStatement node) {
    node.condition.accept(this);
    node.trueBody.accept(this);
    node.falseBody?.accept(this);
  }

  void visitWhileStatement(WhileStatement node) {
    node.condition.accept(this);
    node.body.accept(this);
  }

  void visitForStatement(ForStatement node) {
    node.initExpression?.accept(this);
    node.condition?.accept(this);
    node.loopExpression?.accept(this);
    node.body.accept(this);
  }

  void visitDoWhileStatement(DoWhileStatement node) {
    node.body.accept(this);
    node.condition.accept(this);
  }

  void visitBreakStatement(BreakStatement node) {}
  void visitContinueStatement(ContinueStatement node) {}
  void visitRevertStatement(RevertStatement node) =>
      node.expression.accept(this);
  void visitEmitStatement(EmitStatement node) => node.call.accept(this);
  void visitAssemblyStatement(AssemblyStatement node) {}

  // ── Expressions ────────────────────────────────────────────────────────────
  void visitLiteral(Literal node) {}
  void visitIdentifier(Identifier node) {}
  void visitMemberAccess(MemberAccess node) => node.expression.accept(this);
  void visitIndexAccess(IndexAccess node) {
    node.base.accept(this);
    node.index?.accept(this);
  }

  void visitIndexRangeAccess(IndexRangeAccess node) {
    node.base.accept(this);
    node.start?.accept(this);
    node.end?.accept(this);
  }

  void visitFunctionCall(FunctionCall node) {
    node.expression.accept(this);
    for (final a in node.arguments) a.accept(this);
  }

  void visitFunctionCallOptions(FunctionCallOptions node) {
    node.expression.accept(this);
    for (final v in node.options.values) v.accept(this);
  }

  void visitNewExpression(NewExpression node) {}
  void visitUnaryOperation(UnaryOperation node) =>
      node.subExpression.accept(this);
  void visitBinaryOperation(BinaryOperation node) {
    node.left.accept(this);
    node.right.accept(this);
  }

  void visitAssignment(Assignment node) {
    node.leftHandSide.accept(this);
    node.rightHandSide.accept(this);
  }

  void visitConditional(Conditional node) {
    node.condition.accept(this);
    node.trueExpression.accept(this);
    node.falseExpression.accept(this);
  }

  void visitTypeConversion(TypeConversion node) =>
      node.expression.accept(this);
  void visitTupleExpression(TupleExpression node) {
    for (final c in node.components) c?.accept(this);
  }

  // ── Internal helpers ───────────────────────────────────────────────────────
  void _visitChildren(dynamic node) {
    // Subclasses override specific visit methods rather than this.
  }
}
