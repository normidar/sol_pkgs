/// Yul AST nodes (subset of the full Yul spec).
///
/// See https://docs.soliditylang.org/en/latest/yul.html
sealed class YulNode {}

// ── Top-level ─────────────────────────────────────────────────────────────────

class YulObject extends YulNode {
  YulObject(this.name, this.code, this.subObjects, this.data);

  final String name;
  final YulBlock code;
  final List<YulObject> subObjects;
  final Map<String, List<int>> data; // dataSection name → bytes
}

// ── Statements ────────────────────────────────────────────────────────────────

sealed class YulStatement extends YulNode {}

class YulBlock extends YulStatement {
  YulBlock(this.statements);
  final List<YulStatement> statements;
}

class YulFunctionDefinition extends YulStatement {
  YulFunctionDefinition(
      this.name, this.parameters, this.returnVariables, this.body);

  final String name;
  final List<String> parameters;
  final List<String> returnVariables;
  final YulBlock body;
}

class YulVariableDeclaration extends YulStatement {
  YulVariableDeclaration(this.variables, this.value);

  final List<String> variables;
  final YulExpression? value;
}

class YulAssignment extends YulStatement {
  YulAssignment(this.variables, this.value);

  final List<String> variables;
  final YulExpression value;
}

class YulExpressionStatement extends YulStatement {
  YulExpressionStatement(this.expression);
  final YulExpression expression;
}

class YulIf extends YulStatement {
  YulIf(this.condition, this.body);
  final YulExpression condition;
  final YulBlock body;
}

class YulSwitch extends YulStatement {
  YulSwitch(this.expression, this.cases, this.defaultCase);

  final YulExpression expression;
  final List<YulCase> cases;
  final YulBlock? defaultCase;
}

class YulCase extends YulNode {
  YulCase(this.value, this.body);
  final YulLiteral value;
  final YulBlock body;
}

class YulForLoop extends YulStatement {
  YulForLoop(this.pre, this.condition, this.post, this.body);

  final YulBlock pre;
  final YulExpression condition;
  final YulBlock post;
  final YulBlock body;
}

class YulBreak extends YulStatement {}

class YulContinue extends YulStatement {}

class YulLeave extends YulStatement {}

// ── Expressions ───────────────────────────────────────────────────────────────

sealed class YulExpression extends YulNode {}

class YulLiteral extends YulExpression {
  YulLiteral(this.value, this.kind);
  final String value;
  final YulLiteralKind kind;
}

enum YulLiteralKind { number, string, bool$ }

class YulIdentifier extends YulExpression {
  YulIdentifier(this.name);
  final String name;
}

class YulFunctionCall extends YulExpression {
  YulFunctionCall(this.name, this.arguments);
  final String name;
  final List<YulExpression> arguments;
}
