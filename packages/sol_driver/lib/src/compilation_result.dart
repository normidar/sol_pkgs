import 'dart:typed_data';
import 'package:sol_support/sol_support.dart';

class ContractOutput {
  ContractOutput({
    required this.name,
    required this.bytecode,
    required this.deployedBytecode,
    required this.abi,
    required this.yulIr,
    this.devdoc = const {},
    this.userdoc = const {},
    this.metadata = const {},
    this.deployedSourceMap = '',
  });

  final String name;
  final Uint8List bytecode;
  final Uint8List deployedBytecode;
  final List<Map<String, dynamic>> abi;
  final String yulIr;

  /// solc-compatible developer documentation (from `@dev`/`@param`/`@return`).
  final Map<String, dynamic> devdoc;

  /// solc-compatible end-user documentation (from `@notice`).
  final Map<String, dynamic> userdoc;

  /// solc-compatible contract metadata JSON (abi + docs + settings + sources).
  final Map<String, dynamic> metadata;

  /// solc-format compressed source map for [deployedBytecode]
  /// (`s:l:f:j;...` per instruction). Empty string when the codegen did not
  /// thread locations (e.g. hand-written Yul fixtures).
  final String deployedSourceMap;

  String get bytecodeHex =>
      bytecode.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
}

class CompilationResult {
  CompilationResult({required this.diagnostics, required this.contracts});

  final List<Diagnostic> diagnostics;
  final Map<String, ContractOutput> contracts; // contract name → output

  bool get success => !diagnostics.any((d) => d.isError);

  /// Returns true when compilation succeeded.
  ///
  /// When [warningsAsErrors] is true, any warning is also treated as a failure.
  bool isSuccess({bool warningsAsErrors = false}) {
    if (warningsAsErrors) {
      return !diagnostics.any(
        (d) => d.isError || d.severity == Severity.warning,
      );
    }
    return success;
  }
}
