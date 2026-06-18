import 'dart:typed_data';
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

    test('encodes TupleType', () {
      final enc = AbiEncoder();
      final tupleType = TupleType([uint256Type, boolType]);
      final bytes = enc.encode([
        (tupleType, [BigInt.from(7), true]),
      ]);
      // Tuple is encoded inline: 32 bytes for uint256(7) + 32 bytes for bool(true).
      expect(bytes.length, 64);
      expect(bytes[31], 7); // uint256 = 7
      expect(bytes[63], 1); // bool = true
    });
  });

  group('AbiDecoder', () {
    test('decodes uint256', () {
      final enc = AbiEncoder();
      final dec = AbiDecoder();
      final encoded = enc.encode([(uint256Type, BigInt.from(42))]);
      final result = dec.decode([uint256Type], encoded);
      expect(result.first, BigInt.from(42));
    });

    test('decodes bool', () {
      final enc = AbiEncoder();
      final dec = AbiDecoder();
      final encoded = enc.encode([(boolType, true)]);
      final result = dec.decode([boolType], encoded);
      expect(result.first, isTrue);
    });

    test('decodes address', () {
      final enc = AbiEncoder();
      final dec = AbiDecoder();
      final addr = BigInt.parse(
        '00000000000000000000000000000000000000aa',
        radix: 16,
      );
      final encoded = enc.encode([(addressType, addr)]);
      final result = dec.decode([addressType], encoded);
      expect(result.first, addr);
    });

    test('decodes multiple values', () {
      final enc = AbiEncoder();
      final dec = AbiDecoder();
      final encoded = enc.encode([
        (uint256Type, BigInt.from(1)),
        (uint256Type, BigInt.from(2)),
      ]);
      final result = dec.decode([uint256Type, uint256Type], encoded);
      expect(result[0], BigInt.from(1));
      expect(result[1], BigInt.from(2));
    });

    test('decodes string (dynamic type)', () {
      final enc = AbiEncoder();
      final dec = AbiDecoder();
      final encoded = enc.encode([(stringType, 'hello')]);
      final result = dec.decode([stringType], encoded);
      expect(result.first, 'hello');
    });

    test('round-trips uint256 + string', () {
      final enc = AbiEncoder();
      final dec = AbiDecoder();
      final encoded = enc.encode([
        (uint256Type, BigInt.from(99)),
        (stringType, 'world'),
      ]);
      final result = dec.decode([uint256Type, stringType], encoded);
      expect(result[0], BigInt.from(99));
      expect(result[1], 'world');
    });

    test('decodes fixed-size bytes (bytes4)', () {
      final dec = AbiDecoder();
      // bytes4: 0xdeadbeef stored left-aligned in 32 bytes.
      final data = Uint8List(32)
        ..[0] = 0xde
        ..[1] = 0xad
        ..[2] = 0xbe
        ..[3] = 0xef;
      final result = dec.decode([const BytesNType(4)], data);
      final bytes = result.first as Uint8List;
      expect(bytes[0], 0xde);
      expect(bytes[3], 0xef);
    });

    test('decodes TupleType', () {
      final enc = AbiEncoder();
      final dec = AbiDecoder();
      final tupleType = TupleType([uint256Type, boolType]);
      final encoded = enc.encode([
        (tupleType, [BigInt.from(7), true]),
      ]);
      final result = dec.decode([tupleType], encoded);
      final tuple = result.first as List;
      expect(tuple[0], BigInt.from(7));
      expect(tuple[1], isTrue);
    });
  });
}
