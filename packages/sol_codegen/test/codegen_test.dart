import 'package:sol_ast/sol_ast.dart';
import 'package:sol_codegen/sol_codegen.dart';
import 'package:sol_support/sol_support.dart';
import 'package:sol_yul/sol_yul.dart';
import 'package:test/test.dart';

const loc = SourceLocation(sourceIndex: 0, offset: 0, length: 0);

ContractDefinition makeAdder() => ContractDefinition(
      loc,
      ContractKind.contract,
      'Adder',
      [],
      [
        FunctionDefinition(
          location: loc,
          kind: FunctionKind.function,
          name: 'getSum',
          parameters: [
            Parameter(loc, ElementaryTypeName(loc, 'uint256', intWidth: 256), 'a', null),
            Parameter(loc, ElementaryTypeName(loc, 'uint256', intWidth: 256), 'b', null),
          ],
          returnParameters: [
            Parameter(loc, ElementaryTypeName(loc, 'uint256', intWidth: 256), null, null),
          ],
          visibility: Visibility.public,
          stateMutability: StateMutability.pure,
          isVirtual: false,
          overrideSpecifier: [],
          modifiers: [],
          body: Block(loc, [
            ReturnStatement(
              loc,
              BinaryOperation(loc, '+', Identifier(loc, 'a'), Identifier(loc, 'b')),
            ),
          ]),
        ),
      ],
    );

void main() {
  group('IRGenerator', () {
    test('generates YulObject for contract', () {
      final diagnostics = DiagnosticCollector();
      final obj = IRGenerator(diagnostics).generateContract(makeAdder());
      expect(obj.name, 'Adder');
      expect(obj.subObjects, hasLength(1));
      expect(obj.subObjects.first.name, 'Adder_deployed');
    });

    test('runtime code contains function definition', () {
      final diagnostics = DiagnosticCollector();
      final obj = IRGenerator(diagnostics).generateContract(makeAdder());
      final runtime = obj.subObjects.first;
      final yul = YulPrinter().print(runtime);
      expect(yul, contains('fun_getSum'));
    });

    test('no errors generated', () {
      final diagnostics = DiagnosticCollector();
      IRGenerator(diagnostics).generateContract(makeAdder());
      expect(diagnostics.hasErrors, isFalse);
    });
  });
}
