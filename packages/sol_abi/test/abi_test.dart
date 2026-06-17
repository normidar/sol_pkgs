import 'package:sol_abi/sol_abi.dart';
import 'package:sol_ast/sol_ast.dart';
import 'package:sol_support/sol_support.dart';
import 'package:sol_types/sol_types.dart' hide StateMutability;
import 'package:test/test.dart';

const loc = SourceLocation(sourceIndex: 0, offset: 0, length: 0);

void main() {
  group('AbiGenerator', () {
    test('generates function entry', () {
      final contract = ContractDefinition(
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
            body: null,
          ),
        ],
      );

      final abi = AbiGenerator().generate(contract);
      expect(abi, hasLength(1));
      expect(abi.first['name'], 'getSum');
      expect(abi.first['stateMutability'], 'pure');
      expect((abi.first['inputs'] as List).length, 2);
    });
  });

  group('AbiEncoder', () {
    test('encodes uint256', () {
      final enc = AbiEncoder();
      final bytes = enc.encode([(uint256Type, 42)]);
      expect(bytes.length, 32);
      expect(bytes.last, 42);
    });

    test('encodes bool true', () {
      final enc = AbiEncoder();
      final bytes = enc.encode([(boolType, true)]);
      expect(bytes.last, 1);
    });

    test('encodes two uint256 arguments', () {
      final enc = AbiEncoder();
      final bytes = enc.encode([
        (uint256Type, 1),
        (uint256Type, 2),
      ]);
      expect(bytes.length, 64);
      expect(bytes[31], 1);
      expect(bytes[63], 2);
    });
  });
}
