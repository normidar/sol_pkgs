import 'dart:convert';
import 'package:sol_support/sol_support.dart';
import 'compilation_result.dart';
import 'compiler_stack.dart';

/// Implements the `--standard-json` input/output interface compatible with solc.
///
/// See https://docs.soliditylang.org/en/latest/using-the-compiler.html#compiler-input-and-output-json-description
class StandardJson {
  /// Compiles from a standard-JSON input string and returns the output string.
  String compile(String inputJson) {
    final input = jsonDecode(inputJson) as Map<String, dynamic>;
    final sources = (input['sources'] as Map<String, dynamic>?) ?? {};
    final settings = (input['settings'] as Map<String, dynamic>?) ?? {};
    final outputSelection =
        (settings['outputSelection'] as Map<String, dynamic>?) ?? {};
    final optimize =
        (settings['optimizer'] as Map<String, dynamic>?)?['enabled'] == true;

    final stack = CompilerStack(optimize: optimize);
    for (final entry in sources.entries) {
      final content = (entry.value as Map)['content'] as String? ?? '';
      stack.addSource(entry.key, content);
    }

    final result = stack.compile();
    return jsonEncode(_buildOutput(result, outputSelection));
  }

  Map<String, dynamic> _buildOutput(
    CompilationResult result,
    Map<String, dynamic> outputSelection,
  ) {
    final errors = result.diagnostics
        .map(
          (d) => {
            'type': d.severity == Severity.warning ? 'Warning' : 'Error',
            'severity': d.severity.name,
            'message': d.message,
            'formattedMessage': d.toString(),
          },
        )
        .toList();

    final contracts = <String, dynamic>{};
    for (final entry in result.contracts.entries) {
      contracts[entry.key] = {
        entry.value.name: {
          'abi': entry.value.abi,
          'evm': {
            'bytecode': {'object': entry.value.bytecodeHex},
          },
          'ir': entry.value.yulIr,
        },
      };
    }

    return {'errors': errors, 'contracts': contracts};
  }
}
