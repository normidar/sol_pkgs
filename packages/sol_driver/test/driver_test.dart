import 'dart:convert';
import 'package:sol_driver/sol_driver.dart';
import 'package:sol_support/sol_support.dart';
import 'package:test/test.dart';

const _adderSource = '''
pragma solidity ^0.8.0;
contract Adder {
  function getSum(uint256 a, uint256 b) public pure returns (uint256) {
    return a + b;
  }
}
''';

bool _containsSubsequence(List<int> haystack, List<int> needle) {
  for (var i = 0; i + needle.length <= haystack.length; i++) {
    var match = true;
    for (var j = 0; j < needle.length; j++) {
      if (haystack[i + j] != needle[j]) {
        match = false;
        break;
      }
    }
    if (match) return true;
  }
  return false;
}

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

    test('produces real bytecode for Adder', () {
      final stack = CompilerStack()..addSource('Adder.sol', _adderSource);
      final result = stack.compile();

      // No code-generation errors anywhere in the pipeline.
      expect(
        result.diagnostics.where((d) => d.isError),
        isEmpty,
        reason: result.diagnostics.map((d) => d.message).join('\n'),
      );

      final adder = result.contracts['Adder'];
      expect(adder, isNotNull);
      expect(adder!.bytecode, isNotEmpty);
      expect(adder.deployedBytecode, isNotEmpty);

      // The runtime dispatcher compares against the 4-byte selector of
      // getSum(uint256,uint256) == 0x8e86b125, pushed as PUSH4.
      expect(
        _containsSubsequence(adder.deployedBytecode, [0x8e, 0x86, 0xb1, 0x25]),
        isTrue,
        reason: 'deployed bytecode should embed the getSum selector',
      );

      // Creation bytecode = creation code followed by the runtime code.
      final creation = adder.bytecode;
      final runtime = adder.deployedBytecode;
      expect(creation.length, greaterThan(runtime.length));
      expect(
        creation.sublist(creation.length - runtime.length),
        equals(runtime),
        reason: 'runtime code must be appended to the creation code',
      );
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
            '*': {
              '*': ['abi', 'evm.bytecode'],
            },
          },
        },
      });
      final output = StandardJson().compile(input);
      final decoded = jsonDecode(output) as Map<String, dynamic>;
      expect(decoded.containsKey('contracts'), isTrue);
    });
  });
}
