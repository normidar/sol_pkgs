import 'dart:convert';
import 'dart:typed_data';
import 'package:sol_ast/sol_ast.dart';
import 'package:sol_support/sol_support.dart';
import 'abi_generator.dart';
import 'cbor.dart';
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
    String bytecodeHash = 'none',
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
        'metadata': {'bytecodeHash': bytecodeHash},
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

  /// Encodes a CBOR map suitable for appending to runtime bytecode.
  ///
  /// solc appends `<cbor>||<2-byte big-endian length of cbor>` so the
  /// trailing two bytes locate the start of the metadata blob. We emit the
  /// same trailer here.
  ///
  /// The CBOR map is keyed by `"soldart"` (binary 3-byte version) and the
  /// hash field whose key is determined by [hashAlg] (defaults to
  /// `"keccak256"`). [metadataJson] is the canonical metadata JSON whose
  /// keccak256 is embedded.
  Uint8List encodeMetadataTrailer(
    String metadataJson, {
    String compilerVersion = 'soldart-0.1.0',
    String hashAlg = 'keccak256',
  }) {
    final digest = keccak256OfString(metadataJson);
    final verBytes = _versionTriple(compilerVersion);

    // Insertion-ordered map (CBOR allows any order; we keep it stable).
    final map = <String, Object>{hashAlg: digest, 'soldart': verBytes};
    final cbor = encodeCbor(map);
    final out = BytesBuilder(copy: false);
    out.add(cbor);
    out.addByte((cbor.length >> 8) & 0xff);
    out.addByte(cbor.length & 0xff);
    return out.toBytes();
  }

  /// Parses a version string like `soldart-0.1.0` or `0.8.20+commit.abc` and
  /// returns a 3-byte major/minor/patch triple. Components beyond 255 are
  /// clamped (solc does the same for its CBOR encoding).
  static Uint8List _versionTriple(String v) {
    final m = RegExp(r'(\d+)\.(\d+)\.(\d+)').firstMatch(v);
    int clamp(String? s) {
      final n = int.tryParse(s ?? '0') ?? 0;
      return n < 0 ? 0 : (n > 255 ? 255 : n);
    }

    return Uint8List.fromList([
      clamp(m?.group(1)),
      clamp(m?.group(2)),
      clamp(m?.group(3)),
    ]);
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
    String bytecodeHash = 'none',
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
      bytecodeHash: bytecodeHash,
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
