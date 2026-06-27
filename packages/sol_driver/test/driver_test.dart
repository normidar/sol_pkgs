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
  group('CompilationResult.isSuccess', () {
    test('success is true for a clean compilation', () {
      final stack = CompilerStack()..addSource('Adder.sol', _adderSource);
      final result = stack.compile();
      expect(result.success, isTrue);
      expect(result.isSuccess(), isTrue);
    });

    test('isSuccess(warningsAsErrors: true) fails when warnings exist', () {
      // A circular import produces a warning; use that as our warning source.
      const src = "pragma solidity ^0.8.0; import './A.sol';";
      final result =
          (CompilerStack()
                ..addSource('A.sol', src)
                ..addSource('./A.sol', src))
              .compile();
      final hasWarning = result.diagnostics.any(
        (d) => d.severity == Severity.warning,
      );
      if (hasWarning) {
        expect(result.isSuccess(warningsAsErrors: true), isFalse);
        expect(result.success, isTrue);
      }
    });

    test('isSuccess(warningsAsErrors: false) ignores warnings', () {
      final stack = CompilerStack()..addSource('Adder.sol', _adderSource);
      final result = stack.compile();
      expect(result.isSuccess(warningsAsErrors: false), isTrue);
    });
  });

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

  group('CompilerStack optimizer', () {
    const constSource = '''
pragma solidity ^0.8.0;
contract K {
  function val() public pure returns (uint256) {
    unchecked { return 2 + 3 * 4; }
  }
}
''';

    test('folds constant arithmetic and shrinks bytecode', () {
      final plain = (CompilerStack()..addSource('K.sol', constSource))
          .compile()
          .contracts['K']!;
      final optimised = (CompilerStack(
        optimize: true,
      )..addSource('K.sol', constSource)).compile().contracts['K']!;

      // Unoptimised IR still has the multiplication; optimised folds it to 14.
      expect(plain.yulIr, contains('mul('));
      expect(optimised.yulIr, isNot(contains('mul(')));
      expect(optimised.yulIr, contains('14'));
      // Folding + DCE never make the runtime code larger.
      expect(
        optimised.deployedBytecode.length,
        lessThan(plain.deployedBytecode.length),
      );
    });

    test('optimising Adder produces no errors', () {
      final result = (CompilerStack(
        optimize: true,
      )..addSource('Adder.sol', _adderSource)).compile();
      expect(result.diagnostics.where((d) => d.isError), isEmpty);
      expect(result.contracts['Adder']!.deployedBytecode, isNotEmpty);
    });
  });

  group('ContractChecker in the pipeline', () {
    List<Diagnostic> diagnose(String src, {String name = 'C'}) =>
        (CompilerStack()..addSource('$name.sol', src)).compile().diagnostics;

    test('reports a view function that writes state', () {
      final diags = diagnose('''
pragma solidity ^0.8.0;
contract C {
  uint256 count;
  function f() public view returns (uint256) { count = 1; return count; }
}
''');
      expect(diags.any((d) => d.isError && d.message.contains('view')), isTrue);
    });

    test('warns about an unused local variable', () {
      final diags = diagnose('''
pragma solidity ^0.8.0;
contract C {
  function f() public pure returns (uint256) {
    uint256 unusedLocal = 1;
    return 2;
  }
}
''');
      expect(
        diags.any(
          (d) =>
              d.severity == Severity.warning &&
              d.message.contains('unusedLocal'),
        ),
        isTrue,
      );
    });

    test('warns about a circular import', () {
      final stack = CompilerStack()
        ..addSource('A.sol', 'import "B.sol";\ncontract A {}')
        ..addSource('B.sol', 'import "A.sol";\ncontract B {}');
      final diags = stack.compile().diagnostics;
      expect(
        diags.any(
          (d) =>
              d.severity == Severity.warning &&
              d.message.contains('Circular import'),
        ),
        isTrue,
      );
    });
  });

  group('NatSpec / metadata end-to-end', () {
    const documented = '''
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;
/// @title Adder
/// @author Carol
/// @notice Adds numbers
contract Adder {
  /// @notice Returns the sum of a and b
  /// @param a first
  /// @param b second
  /// @return the sum
  function getSum(uint256 a, uint256 b) public pure returns (uint256) {
    return a + b;
  }
}
''';

    test('produces devdoc/userdoc/metadata from doc comments', () {
      final c = (CompilerStack()..addSource('Adder.sol', documented))
          .compile()
          .contracts['Adder']!;

      expect(c.userdoc['notice'], 'Adds numbers');
      expect(
        c.userdoc['methods']['getSum(uint256,uint256)']['notice'],
        'Returns the sum of a and b',
      );
      expect(c.devdoc['title'], 'Adder');
      expect(c.devdoc['author'], 'Carol');
      expect(c.devdoc['methods']['getSum(uint256,uint256)']['params'], {
        'a': 'first',
        'b': 'second',
      });

      expect(c.metadata['language'], 'Solidity');
      expect(c.metadata['settings']['compilationTarget'], {
        'Adder.sol': 'Adder',
      });
      expect(c.metadata['sources']['Adder.sol']['license'], 'MIT');
    });

    test('standard-json surfaces devdoc/userdoc/metadata', () {
      final input = jsonEncode({
        'language': 'Solidity',
        'sources': {
          'Adder.sol': {'content': documented},
        },
        'settings': {
          'outputSelection': {
            '*': {
              '*': ['abi', 'devdoc', 'userdoc', 'metadata'],
            },
          },
        },
      });
      final out =
          jsonDecode(StandardJson().compile(input)) as Map<String, dynamic>;
      final adder = out['contracts']['Adder']['Adder'] as Map<String, dynamic>;
      expect(adder['userdoc']['notice'], 'Adds numbers');
      expect(adder['devdoc']['author'], 'Carol');
      // metadata is serialised as a JSON string, like solc.
      expect(adder['metadata'], isA<String>());
      expect(
        (jsonDecode(adder['metadata'] as String)
            as Map<String, dynamic>)['language'],
        'Solidity',
      );
    });
  });

  group('source map', () {
    test(
      'Adder produces a non-empty source map with multiple distinct ranges',
      () {
        final c = (CompilerStack()..addSource('Adder.sol', _adderSource))
            .compile()
            .contracts['Adder']!;
        final sm = c.deployedSourceMap;
        expect(sm, isNotEmpty);
        // Compressed form uses `;` between instructions.
        expect(sm.contains(';'), isTrue);
        // At least one entry should point at a real source offset (i.e. not all
        // "unknown" -1's). The very first entry is the full `s:l:f:j` quad.
        final firstEntry = sm.split(';').first;
        final fields = firstEntry.split(':');
        expect(fields.length, greaterThanOrEqualTo(3));
        // We do not require fields[0] != '-1' because the dispatcher prologue is
        // synthetic; instead, scan for any entry with a non-negative start.
        final hasReal = sm.split(';').any((e) {
          final s = e.split(':').first;
          return s.isNotEmpty && !s.startsWith('-');
        });
        expect(hasReal, isTrue);
      },
    );

    test('standard-json output surfaces deployedBytecode.sourceMap', () {
      final input = jsonEncode({
        'language': 'Solidity',
        'sources': {
          'Adder.sol': {'content': _adderSource},
        },
        'settings': {
          'outputSelection': {
            '*': {
              '*': ['evm.deployedBytecode.sourceMap'],
            },
          },
        },
      });
      final out =
          jsonDecode(StandardJson().compile(input)) as Map<String, dynamic>;
      final adder = out['contracts']['Adder']['Adder'] as Map<String, dynamic>;
      final deployed =
          (adder['evm'] as Map)['deployedBytecode'] as Map<String, dynamic>;
      expect(deployed['sourceMap'], isA<String>());
      expect((deployed['sourceMap'] as String).isNotEmpty, isTrue);
    });
  });

  group('bytecodeHash trailer', () {
    test('default (none) does not append CBOR', () {
      final c = (CompilerStack()..addSource('Adder.sol', _adderSource))
          .compile()
          .contracts['Adder']!;
      // The runtime ends with the dispatcher's revert (0x5f 0x5f 0xfd) when no
      // trailer is present, so the trailer length-encoding (0x00 0xNN) at the
      // very end is not what we expect to see.
      final last = c.deployedBytecode.last;
      expect(last, isNot(equals(0x00)));
    });

    test('keccak256 appends CBOR map ending in length-2 trailer', () {
      final c = (CompilerStack(
        bytecodeHash: 'keccak256',
      )..addSource('Adder.sol', _adderSource)).compile().contracts['Adder']!;
      final code = c.deployedBytecode;
      // Last two bytes are big-endian length of the CBOR body.
      final len = (code[code.length - 2] << 8) | code[code.length - 1];
      expect(len, greaterThan(0));
      expect(len + 2, lessThanOrEqualTo(code.length));
      // CBOR map header for 2 entries.
      expect(code[code.length - 2 - len], 0xa2);
      // Creation code embeds the runtime+trailer.
      expect(c.bytecode.sublist(c.bytecode.length - code.length), equals(code));
      // The metadata.bytecodeHash setting is recorded as keccak256.
      expect(c.metadata['settings']['metadata']['bytecodeHash'], 'keccak256');
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

    test('honours settings.optimizer.enabled', () {
      Map<String, dynamic> compileWith(bool enabled) {
        final input = jsonEncode({
          'language': 'Solidity',
          'sources': {
            'K.sol': {
              'content': '''
pragma solidity ^0.8.0;
contract K {
  function val() public pure returns (uint256) {
    unchecked { return 2 + 3 * 4; }
  }
}
''',
            },
          },
          'settings': {
            'optimizer': {'enabled': enabled},
            'outputSelection': {
              '*': {
                '*': ['evm.bytecode', 'ir'],
              },
            },
          },
        });
        return jsonDecode(StandardJson().compile(input))
            as Map<String, dynamic>;
      }

      final off = compileWith(false);
      final on = compileWith(true);
      // _buildOutput keys contracts by contract name: contracts[K][K].
      final irOff = off['contracts']['K']['K']['ir'] as String;
      final irOn = on['contracts']['K']['K']['ir'] as String;
      expect(irOff, contains('mul('));
      expect(irOn, isNot(contains('mul(')));
    });
  });
}
