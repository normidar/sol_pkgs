import 'declarations.dart';
import 'expressions.dart';
import 'statements.dart';
import 'type_names.dart';

/// Double-dispatch visitor.  Override only the nodes you care about;
/// the default implementation walks children where it makes sense.
abstract class AstVisitor {
  // ── Declarations ──────────────────────────────────────────────────────────

  void visitSourceFile(SourceFile node) {
    for (final p in node.pragmas) p.accept(this);
    for (final i in node.imports) i.accept(this);
    for (final c in node.declarations) c.accept(this);
  }

  void visitPragmaDirective(PragmaDirective node) {}
  void visitImportDirective(ImportDirective node) {}

  void visitContractDefinition(ContractDefinition node) {
    for (final b in node.baseContracts) b.accept(this);
    for (final m in node.members) m.accept(this);
  }

  void visitInheritanceSpecifier(InheritanceSpecifier node) {
    for (final a in node.arguments) a.accept(this);
  }

  void visitFunctionDefinition(FunctionDefinition node) {
    for (final p in node.parameters) p.accept(this);
    for (final r in node.returnParameters) r.accept(this);
    for (final m in node.modifiers) m.accept(this);
    node.body?.accept(this);
  }

  void visitModifierDefinition(ModifierDefinition node) {
    for (final p in node.parameters) p.accept(this);
    node.body.accept(this);
  }

  void visitModifierInvocation(ModifierInvocation node) {
    for (final a in node.arguments) a.accept(this);
  }

  void visitStateVariableDeclaration(StateVariableDeclaration node) {
    node.typeName.accept(this);
    node.initialValue?.accept(this);
  }

  void visitEventDefinition(EventDefinition node) {
    for (final p in node.parameters) p.accept(this);
  }

  void visitCustomErrorDefinition(CustomErrorDefinition node) {
    for (final p in node.parameters) p.accept(this);
  }

  void visitStructDefinition(StructDefinition node) {
    for (final m in node.members) m.accept(this);
  }

  void visitEnumDefinition(EnumDefinition node) {}

  void visitUsingDirective(UsingDirective node) {
    node.typeName?.accept(this);
  }

  void visitUserDefinedValueTypeDefinition(
      UserDefinedValueTypeDefinition node) {
    node.underlyingType.accept(this);
  }

  // ── Type names ────────────────────────────────────────────────────────────

  void visitElementaryTypeName(ElementaryTypeName node) {}

  void visitArrayTypeName(ArrayTypeName node) {
    node.baseType.accept(this);
    node.length?.accept(this);
  }

  void visitMappingTypeName(MappingTypeName node) {
    node.keyType.accept(this);
    node.valueType.accept(this);
  }

  void visitUserDefinedTypeName(UserDefinedTypeName node) {}

  void visitFunctionTypeName(FunctionTypeName node) {
    for (final p in node.parameters) p.accept(this);
    for (final r in node.returnParameters) r.accept(this);
  }

  void visitParameter(Parameter node) {
    node.typeName.accept(this);
  }

  void visitVariableDeclaration(VariableDeclaration node) {
    node.typeName.accept(this);
  }

  // ── Statements ────────────────────────────────────────────────────────────

  void visitBlock(Block node) {
    for (final s in node.statements) s.accept(this);
  }

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
    node.initStatement?.accept(this);
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

  void visitReturnStatement(ReturnStatement node) {
    node.expression?.accept(this);
  }

  void visitExpressionStatement(ExpressionStatement node) {
    node.expression.accept(this);
  }

  void visitVariableDeclarationStatement(
      VariableDeclarationStatement node) {
    for (final d in node.declarations) d?.accept(this);
    node.initialValue?.accept(this);
  }

  void visitRevertStatement(RevertStatement node) {
    node.expression.accept(this);
  }

  void visitEmitStatement(EmitStatement node) {
    node.call.accept(this);
  }

  void visitUncheckedStatement(UncheckedStatement node) {
    node.body.accept(this);
  }

  void visitAssemblyStatement(AssemblyStatement node) {}

  void visitTryStatement(TryStatement node) {
    node.externalCall.accept(this);
    for (final c in node.clauses) c.accept(this);
  }

  void visitCatchClause(CatchClause node) {
    for (final p in node.parameters) p.accept(this);
    node.body.accept(this);
  }

  // ── Expressions ───────────────────────────────────────────────────────────

  void visitLiteral(Literal node) {}
  void visitIdentifier(Identifier node) {}

  void visitMemberAccess(MemberAccess node) {
    node.expression.accept(this);
  }

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

  void visitNewExpression(NewExpression node) {
    node.typeName.accept(this);
  }

  void visitUnaryOperation(UnaryOperation node) {
    node.subExpression.accept(this);
  }

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

  void visitTypeConversion(TypeConversion node) {
    node.typeName.accept(this);
    node.expression.accept(this);
  }

  void visitTupleExpression(TupleExpression node) {
    for (final c in node.components) c?.accept(this);
  }

  void visitDeleteExpression(DeleteExpression node) {
    node.expression.accept(this);
  }

  void visitTypeExpression(TypeExpression node) {
    node.typeName.accept(this);
  }
}
