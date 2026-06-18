import 'package:sol_abi/sol_abi.dart';
import 'package:sol_ast/sol_ast.dart';
import 'package:sol_codegen/sol_codegen.dart';
import 'package:sol_lexer/sol_lexer.dart';
import 'package:sol_parser/sol_parser.dart';
import 'package:sol_sema/sol_sema.dart';
import 'package:sol_support/sol_support.dart';
import 'package:sol_yul/sol_yul.dart';
import 'compilation_result.dart';

/// Orchestrates all compiler phases for a set of Solidity source files.
///
/// Usage:
/// ```dart
/// final result = CompilerStack()
///   ..addSource('Adder.sol', source)
///   ..compile();
/// ```
class CompilerStack {
  final SourceUnitRegistry _registry = SourceUnitRegistry();
  final DiagnosticCollector _diagnostics = DiagnosticCollector();
  final Map<String, String> _sources = {};

  void addSource(String path, String source) {
    _sources[path] = source;
  }

  CompilationResult compile() {
    final contracts = <String, ContractOutput>{};

    try {
      for (final entry in _sources.entries) {
        final unit = _registry.add(entry.key, entry.value);
        final ast = _parse(unit);
        if (ast == null) continue;

        _analyse(ast);
        if (_diagnostics.hasErrors) continue;

        for (final contract in ast.declarations) {
          final output = _compileContract(contract);
          if (output != null) {
            contracts[contract.name] = output;
          }
        }
      }
    } on FatalErrorException catch (e) {
      _diagnostics.error(e.diagnostic.message, location: e.diagnostic.location);
    }

    return CompilationResult(
      diagnostics: _diagnostics.diagnostics,
      contracts: contracts,
    );
  }

  SourceFile? _parse(SourceUnit unit) {
    try {
      final tokens = Lexer(
        source: unit.source,
        sourceIndex: unit.index,
      ).tokenize();
      return Parser(
        tokens: tokens,
        sourceIndex: unit.index,
        diagnostics: _diagnostics,
      ).parse();
    } catch (e) {
      _diagnostics.error('Parse failed: $e');
      return null;
    }
  }

  void _analyse(SourceFile ast) {
    try {
      Resolver(_diagnostics).resolve(ast);
      if (!_diagnostics.hasErrors) {
        TypeChecker(_diagnostics).visitSourceFile(ast);
      }
    } on FatalErrorException {
      // already recorded
    }
  }

  ContractOutput? _compileContract(ContractDefinition contract) {
    try {
      final yulObj = IRGenerator(_diagnostics).generateContract(contract);
      final yulIr = YulPrinter().print(yulObj);
      final bytecode = YulCodeGenerator().generate(yulObj);
      final deployedBytecode = YulCodeGenerator().generateDeployed(yulObj);
      final abi = AbiGenerator().generate(contract);

      return ContractOutput(
        name: contract.name,
        bytecode: bytecode,
        deployedBytecode: deployedBytecode,
        abi: abi,
        yulIr: yulIr,
      );
    } catch (e) {
      _diagnostics.error('Code generation failed for ${contract.name}: $e');
      return null;
    }
  }
}
