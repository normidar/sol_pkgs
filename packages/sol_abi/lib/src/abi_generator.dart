import 'dart:convert';
import 'package:sol_ast/sol_ast.dart';
import 'abi_signature.dart';

/// Generates the Solidity ABI JSON for a [ContractDefinition].
///
/// Output matches the format expected by ethers.js, viem, and solc itself.
class AbiGenerator {
  List<Map<String, dynamic>> generate(ContractDefinition contract) {
    final entries = <Map<String, dynamic>>[];

    for (final member in contract.members) {
      switch (member) {
        case FunctionDefinition fn when fn.name != null:
          if (fn.visibility == Visibility.public ||
              fn.visibility == Visibility.external) {
            entries.add(_functionEntry(fn));
          }
        case EventDefinition ev:
          entries.add(_eventEntry(ev));
        case CustomErrorDefinition err:
          entries.add(_errorEntry(err));
        default:
          break;
      }
    }

    return entries;
  }

  /// Returns the ABI JSON as a formatted string.
  String generateJson(ContractDefinition contract) =>
      const JsonEncoder.withIndent('  ').convert(generate(contract));

  Map<String, dynamic> _functionEntry(FunctionDefinition fn) => {
        'type': 'function',
        'name': fn.name,
        'inputs': fn.parameters.map(_paramEntry).toList(),
        'outputs': fn.returnParameters.map(_paramEntry).toList(),
        'stateMutability': fn.stateMutability.name,
      };

  Map<String, dynamic> _eventEntry(EventDefinition ev) => {
        'type': 'event',
        'name': ev.name,
        'inputs': ev.parameters.map((p) {
          final entry = _paramEntry(p);
          entry['indexed'] = p.indexed;
          return entry;
        }).toList(),
        'anonymous': ev.anonymous,
      };

  Map<String, dynamic> _errorEntry(CustomErrorDefinition err) => {
        'type': 'error',
        'name': err.name,
        'inputs': err.parameters.map(_paramEntry).toList(),
      };

  Map<String, dynamic> _paramEntry(Parameter p) => {
        'name': p.name ?? '',
        'type': _typeString(p.typeName),
      };

  String _typeString(TypeName typeName) {
    // Mappings never appear in an ABI; everything else uses the canonical form.
    if (typeName is MappingTypeName) return 'mapping';
    return abiCanonicalType(typeName);
  }
}
