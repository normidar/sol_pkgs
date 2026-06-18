import 'package:sol_ast/sol_ast.dart';
import 'package:sol_support/sol_support.dart';
import 'package:test/test.dart';

const loc = SourceLocation(sourceIndex: 0, offset: 0, length: 0);

void main() {
  group('AstVisitor', () {
    test('visits binary operation children', () {
      final visited = <String>[];
      final expr = BinaryOperation(
        loc,
        '+',
        Identifier(loc, 'a'),
        Identifier(loc, 'b'),
      );

      final visitor = _RecordVisitor(visited);
      expr.accept(visitor);
      expect(visited, ['a', 'b']);
    });

    test('visits function body via block', () {
      final visited = <String>[];
      final fn = FunctionDefinition(
        location: loc,
        kind: FunctionKind.function,
        name: 'getSum',
        parameters: [],
        returnParameters: [],
        visibility: Visibility.public,
        stateMutability: StateMutability.pure,
        isVirtual: false,
        overrideSpecifier: [],
        modifiers: [],
        body: Block(loc, [
          ReturnStatement(
            loc,
            BinaryOperation(
              loc,
              '+',
              Identifier(loc, 'a'),
              Identifier(loc, 'b'),
            ),
          ),
        ]),
      );

      final visitor = _RecordVisitor(visited);
      fn.accept(visitor);
      expect(visited, ['a', 'b']);
    });
  });
}

class _RecordVisitor extends AstVisitor {
  _RecordVisitor(this.log);

  final List<String> log;

  @override
  void visitIdentifier(Identifier node) => log.add(node.name);

  @override
  void visitFunctionDefinition(FunctionDefinition node) =>
      node.body?.accept(this);
}
