import 'yul_ast.dart';

/// Pretty-prints Yul AST back to Yul source text (for debugging / IR output).
class YulPrinter {
  final _buf = StringBuffer();
  int _indent = 0;

  String print(YulNode node) {
    _visit(node);
    return _buf.toString();
  }

  void _visit(YulNode node) {
    switch (node) {
      case YulObject(:final name, :final code, :final subObjects):
        _write('object "$name" {\n');
        _indent++;
        _write('code ');
        _visit(code);
        for (final sub in subObjects) _visit(sub);
        _indent--;
        _write('}\n');

      case YulBlock(:final statements):
        _write('{\n');
        _indent++;
        for (final s in statements) {
          _writeIndent();
          _visit(s);
          _write('\n');
        }
        _indent--;
        _writeIndent();
        _write('}');

      case YulFunctionDefinition(:final name, :final parameters,
              :final returnVariables, :final body):
        _write('function $name(${parameters.join(', ')})');
        if (returnVariables.isNotEmpty) {
          _write(' -> ${returnVariables.join(', ')}');
        }
        _write(' ');
        _visit(body);

      case YulVariableDeclaration(:final variables, :final value):
        _write('let ${variables.join(', ')}');
        if (value != null) {
          _write(' := ');
          _visit(value);
        }

      case YulAssignment(:final variables, :final value):
        _write('${variables.join(', ')} := ');
        _visit(value);

      case YulExpressionStatement(:final expression):
        _visit(expression);

      case YulIf(:final condition, :final body):
        _write('if ');
        _visit(condition);
        _write(' ');
        _visit(body);

      case YulSwitch(:final expression, :final cases, :final defaultCase):
        _write('switch ');
        _visit(expression);
        _write('\n');
        for (final c in cases) {
          _writeIndent();
          _write('case ');
          _visit(c.value);
          _write(' ');
          _visit(c.body);
          _write('\n');
        }
        if (defaultCase != null) {
          _writeIndent();
          _write('default ');
          _visit(defaultCase);
        }

      case YulForLoop(:final pre, :final condition, :final post, :final body):
        _write('for ');
        _visit(pre);
        _write(' ');
        _visit(condition);
        _write(' ');
        _visit(post);
        _write(' ');
        _visit(body);

      case YulBreak():
        _write('break');

      case YulContinue():
        _write('continue');

      case YulLeave():
        _write('leave');

      case YulLiteral(:final value):
        _write(value);

      case YulIdentifier(:final name):
        _write(name);

      case YulFunctionCall(:final name, :final arguments):
        _write('$name(');
        for (var i = 0; i < arguments.length; i++) {
          if (i > 0) _write(', ');
          _visit(arguments[i]);
        }
        _write(')');

      case YulCase():
        // handled inline in YulSwitch
        break;
    }
  }

  void _write(String s) => _buf.write(s);
  void _writeIndent() => _buf.write('  ' * _indent);
}
