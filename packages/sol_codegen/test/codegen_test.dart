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

    test('dispatcher uses the real keccak256 selector (B-5)', () {
      final obj = IRGenerator(DiagnosticCollector()).generateContract(makeAdder());
      final yul = YulPrinter().print(obj);
      // keccak256("getSum(uint256,uint256)")[:4] == 0x8e86b125
      expect(yul, contains('case 0x8e86b125'));
    });

    test('decodes each argument at its own calldata offset (B-6)', () {
      final obj = IRGenerator(DiagnosticCollector()).generateContract(makeAdder());
      final yul = YulPrinter().print(obj);
      expect(yul, contains('calldataload(4)')); // arg 0
      expect(yul, contains('calldataload(36)')); // arg 1
    });

    test('ABI-encodes the return value into memory then returns it', () {
      final obj = IRGenerator(DiagnosticCollector()).generateContract(makeAdder());
      final yul = YulPrinter().print(obj);
      expect(yul, contains('mstore(0,'));
      expect(yul, contains('return(0, 32)'));
    });

    test('lowers to valid bytecode embedding the selector', () {
      final obj = IRGenerator(DiagnosticCollector()).generateContract(makeAdder());
      final bytecode = YulCodeGenerator().generate(obj);
      expect(bytecode, isNotEmpty);
      // PUSH4 selector and per-argument CALLDATALOAD offsets appear in code.
      expect(_subseq(bytecode, [0x8e, 0x86, 0xb1, 0x25]), isTrue);
      expect(_subseq(bytecode, [0x60, 0x04, 0x35]), isTrue); // calldataload(4)
      expect(_subseq(bytecode, [0x60, 0x24, 0x35]), isTrue); // calldataload(36)
    });
  });
}

bool _subseq(List<int> haystack, List<int> needle) {
  for (var i = 0; i + needle.length <= haystack.length; i++) {
    var ok = true;
    for (var j = 0; j < needle.length; j++) {
      if (haystack[i + j] != needle[j]) {
        ok = false;
        break;
      }
    }
    if (ok) return true;
  }
  return false;
}
