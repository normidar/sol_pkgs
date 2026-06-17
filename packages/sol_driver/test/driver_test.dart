import 'dart:convert';
import 'package:sol_driver/sol_driver.dart';
import 'package:test/test.dart';

const _adderSource = '''
pragma solidity ^0.8.0;
contract Adder {
  function getSum(uint256 a, uint256 b) public pure returns (uint256) {
    return a + b;
  }
}
''';

void main() {
  group('CompilerStack', () {
    test('compiles Adder without fatal errors', () {
      final stack = CompilerStack()..addSource('Adder.sol', _adderSource);
      final result = stack.compile();
      expect(
        result.diagnostics.where((d) => d.severity == Severity.fatalError),
        isEmpty,
      );
    });

    test('returns compilation result', () {
      final stack = CompilerStack()..addSource('Adder.sol', _adderSource);
      final result = stack.compile();
      expect(result, isNotNull);
    });
  });

  group('StandardJson', () {
    test('round-trips standard-json format', () {
      final input = jsonEncode({
        'language': 'Solidity',
        'sources': {
          'Adder.sol': {'content': _adderSource},
        },
        'settings': {
          'outputSelection': {
            '*': {'*': ['abi', 'evm.bytecode']},
          },
        },
      });
      final output = StandardJson().compile(input);
      final decoded = jsonDecode(output) as Map<String, dynamic>;
      expect(decoded, containsKey('contracts'));
    });
  });
}
