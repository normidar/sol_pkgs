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
              Parameter(
                loc,
                ElementaryTypeName(loc, 'uint256', intWidth: 256),
                'a',
                null,
              ),
              Parameter(
                loc,
                ElementaryTypeName(loc, 'uint256', intWidth: 256),
                'b',
                null,
              ),
            ],
            returnParameters: [
              Parameter(
                loc,
                ElementaryTypeName(loc, 'uint256', intWidth: 256),
                null,
                null,
              ),
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

    test('marks indexed event parameters', () {
      final contract = ContractDefinition(
        loc,
        ContractKind.contract,
        'Token',
        [],
        [
          EventDefinition(loc, 'Transfer', [
            Parameter(
              loc,
              ElementaryTypeName(loc, 'address'),
              'from',
              null,
              indexed: true,
            ),
            Parameter(
              loc,
              ElementaryTypeName(loc, 'address'),
              'to',
              null,
              indexed: true,
            ),
            Parameter(
              loc,
              ElementaryTypeName(loc, 'uint256', intWidth: 256),
              'value',
              null,
            ),
          ], false),
        ],
      );

      final abi = AbiGenerator().generate(contract);
      final inputs = abi.first['inputs'] as List;
      expect(inputs[0]['indexed'], isTrue);
      expect(inputs[1]['indexed'], isTrue);
      expect(inputs[2]['indexed'], isFalse);
    });

    test('renders fixed-length array types', () {
      final contract = ContractDefinition(loc, ContractKind.contract, 'C', [], [
        FunctionDefinition(
          location: loc,
          kind: FunctionKind.function,
          name: 'f',
          parameters: [
            Parameter(
              loc,
              ArrayTypeName(
                loc,
                ElementaryTypeName(loc, 'uint256', intWidth: 256),
                Literal(loc, LiteralKind.number, '3', null),
              ),
              'xs',
              DataLocation.memory,
            ),
          ],
          returnParameters: [],
          visibility: Visibility.public,
          stateMutability: StateMutability.pure,
          isVirtual: false,
          overrideSpecifier: [],
          modifiers: [],
          body: null,
        ),
      ]);

      final abi = AbiGenerator().generate(contract);
      expect((abi.first['inputs'] as List).first['type'], 'uint256[3]');
    });
  });

  group('abi signatures', () {
    test('computes canonical function selector', () {
      final fn = FunctionDefinition(
        location: loc,
        kind: FunctionKind.function,
        name: 'transfer',
        parameters: [
          Parameter(loc, ElementaryTypeName(loc, 'address'), 'to', null),
          Parameter(
            loc,
            ElementaryTypeName(loc, 'uint', intWidth: 0),
            'amount',
            null,
          ),
        ],
        returnParameters: [],
        visibility: Visibility.external,
        stateMutability: StateMutability.nonpayable,
        isVirtual: false,
        overrideSpecifier: [],
        modifiers: [],
        body: null,
      );
      // `uint` must canonicalise to `uint256` → transfer(address,uint256).
      expect(functionSignature(fn), 'transfer(address,uint256)');
      expect(functionSelectorHex(fn), '0xa9059cbb');
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
      final bytes = enc.encode([(uint256Type, 1), (uint256Type, 2)]);
      expect(bytes.length, 64);
      expect(bytes[31], 1);
      expect(bytes[63], 2);
    });
  });
}
