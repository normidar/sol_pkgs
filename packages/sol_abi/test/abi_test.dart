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

  group('NatSpec.parse', () {
    test('implicit notice from untagged text', () {
      final ns = NatSpec.parse('Adds two numbers together.');
      expect(ns.notice, 'Adds two numbers together.');
    });

    test('parses the standard tags', () {
      final ns = NatSpec.parse('''
@title Math
@author Alice
@notice Adds two numbers
@dev Uses checked arithmetic
@param a The first addend
@param b The second addend
@return The sum''');
      expect(ns.title, 'Math');
      expect(ns.author, 'Alice');
      expect(ns.notice, 'Adds two numbers');
      expect(ns.dev, 'Uses checked arithmetic');
      expect(ns.params, {'a': 'The first addend', 'b': 'The second addend'});
      expect(ns.returns, ['The sum']);
    });

    test('collapses multi-line tag content', () {
      final ns = NatSpec.parse('@dev line one\n     line two');
      expect(ns.dev, 'line one line two');
    });

    test('captures @custom: tags', () {
      final ns = NatSpec.parse('@custom:security audited by X');
      expect(ns.custom, {'security': 'audited by X'});
    });

    test('empty for null/blank input', () {
      expect(NatSpec.parse(null).isEmpty, isTrue);
      expect(NatSpec.parse('   ').isEmpty, isTrue);
    });
  });

  group('DocGenerator', () {
    ContractDefinition documentedContract() {
      final getSum =
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
            )
            ..documentation =
                '@notice Adds a and b\n@param a first\n@param b second\n@return the sum';

      final transfer = EventDefinition(loc, 'Transfer', [
        Parameter(loc, ElementaryTypeName(loc, 'address'), 'to', null),
      ], false)..documentation = '@notice Emitted on transfer';

      return ContractDefinition(loc, ContractKind.contract, 'Math', [], [
        getSum,
        transfer,
      ])..documentation = '@title Math library\n@author Bob\n@notice Does math';
    }

    test('userdoc carries @notice for contract and methods', () {
      final ud = DocGenerator().userdoc(documentedContract());
      expect(ud['kind'], 'user');
      expect(ud['notice'], 'Does math');
      expect(
        ud['methods']['getSum(uint256,uint256)']['notice'],
        'Adds a and b',
      );
      expect(
        ud['events']['Transfer(address)']['notice'],
        'Emitted on transfer',
      );
    });

    test('devdoc carries title/author/params/returns', () {
      final dd = DocGenerator().devdoc(documentedContract());
      expect(dd['kind'], 'dev');
      expect(dd['title'], 'Math library');
      expect(dd['author'], 'Bob');
      final method = dd['methods']['getSum(uint256,uint256)'];
      expect(method['params'], {'a': 'first', 'b': 'second'});
      // Unnamed single return is keyed _0.
      expect(method['returns'], {'_0': 'the sum'});
    });
  });

  group('MetadataGenerator', () {
    test('produces solc-shaped metadata with source hash and abi', () {
      const source = '''
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;
contract Empty {}
''';
      final contract = ContractDefinition(
        loc,
        ContractKind.contract,
        'Empty',
        [],
        [],
      )..documentation = '@title Empty';
      final meta = const MetadataGenerator().generate(
        sourcePath: 'Empty.sol',
        sourceContent: source,
        contract: contract,
        optimizerEnabled: true,
        optimizerRuns: 200,
      );

      expect(meta['language'], 'Solidity');
      expect(meta['version'], 1);
      expect(meta['settings']['compilationTarget'], {'Empty.sol': 'Empty'});
      expect(meta['settings']['optimizer'], {'enabled': true, 'runs': 200});
      expect(meta['output']['abi'], isA<List>());
      expect(meta['output']['devdoc']['title'], 'Empty');
      final src = meta['sources']['Empty.sol'] as Map<String, dynamic>;
      expect((src['keccak256'] as String).startsWith('0x'), isTrue);
      expect(src['license'], 'MIT');
    });
  });
}
