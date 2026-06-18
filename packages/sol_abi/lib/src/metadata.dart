import 'dart:convert';
import 'package:sol_ast/sol_ast.dart';
import 'package:sol_support/sol_support.dart';
import 'abi_generator.dart';
import 'doc_generator.dart';

/// Generates a solc-compatible contract metadata JSON document.
///
/// The metadata is the structure solc embeds (hashed) at the end of bytecode
/// and that verification services consume. It bundles the ABI, NatSpec
/// (devdoc/userdoc), compiler settings, and per-source keccak256 hashes.
///
/// See https://docs.soliditylang.org/en/latest/metadata.html
class MetadataGenerator {
  const MetadataGenerator();

  Map<String, dynamic> generate({
    required String sourcePath,
    required String sourceContent,
    required ContractDefinition contract,
    bool optimizerEnabled = false,
    int optimizerRuns = 200,
    String evmVersion = 'cancun',
    String compilerVersion = 'soldart-0.1.0',
    List<String> remappings = const [],
  }) {
    final abi = AbiGenerator().generate(contract);
    final docs = DocGenerator();
    final hash = keccak256HexOfString(sourceContent);
    final license = _extractLicense(sourceContent);

    return {
      'compiler': {'version': compilerVersion},
      'language': 'Solidity',
      'output': {
        'abi': abi,
        'devdoc': docs.devdoc(contract),
        'userdoc': docs.userdoc(contract),
      },
      'settings': {
        'compilationTarget': {sourcePath: contract.name},
        'evmVersion': evmVersion,
        'libraries': <String, String>{},
        // We do not append a metadata hash to bytecode, so record "none".
        'metadata': {'bytecodeHash': 'none'},
        'optimizer': {'enabled': optimizerEnabled, 'runs': optimizerRuns},
        'remappings': remappings,
      },
      'sources': {
        sourcePath: {
          'keccak256': '0x$hash',
          if (license != null) 'license': license,
        },
      },
      'version': 1,
    };
  }

  /// Returns the metadata as a compact JSON string (solc emits it minified and
  /// with sorted keys; we keep insertion order, which is still valid JSON).
  String generateJson({
    required String sourcePath,
    required String sourceContent,
    required ContractDefinition contract,
    bool optimizerEnabled = false,
    int optimizerRuns = 200,
    String evmVersion = 'cancun',
    String compilerVersion = 'soldart-0.1.0',
    List<String> remappings = const [],
  }) => jsonEncode(
    generate(
      sourcePath: sourcePath,
      sourceContent: sourceContent,
      contract: contract,
      optimizerEnabled: optimizerEnabled,
      optimizerRuns: optimizerRuns,
      evmVersion: evmVersion,
      compilerVersion: compilerVersion,
      remappings: remappings,
    ),
  );

  /// Extracts the `SPDX-License-Identifier` from the source, if present.
  static String? _extractLicense(String source) {
    final m = RegExp(
      r'SPDX-License-Identifier:\s*([^\s*]+)',
    ).firstMatch(source);
    return m?.group(1);
  }
}
