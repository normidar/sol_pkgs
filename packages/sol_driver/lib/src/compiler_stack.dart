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
  CompilerStack({this.optimize = false});

  /// When true, the generated Yul IR is run through [YulOptimizer] before
  /// bytecode generation (constant folding, simplification, dead-code
  /// elimination). Mirrors solc's `settings.optimizer.enabled`.
  final bool optimize;

  final SourceUnitRegistry _registry = SourceUnitRegistry();
  final DiagnosticCollector _diagnostics = DiagnosticCollector();
  final Map<String, String> _sources = {};

  void addSource(String path, String source) {
    _sources[path] = source;
  }

  CompilationResult compile() {
    final contracts = <String, ContractOutput>{};

    try {
      // First pass: parse all provided sources.
      final asts = <String, SourceFile>{};
      for (final entry in _sources.entries) {
        final unit = _registry.add(entry.key, entry.value);
        final ast = _parse(unit);
        if (ast != null) asts[entry.key] = ast;
      }

      // Resolve imports: add transitively imported sources.
      _resolveImports(asts);

      // Second pass: analyse and compile.
      for (final entry in asts.entries) {
        _analyse(entry.value);
        if (_diagnostics.hasErrors) continue;

        for (final contract in entry.value.declarations) {
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

  void _resolveImports(Map<String, SourceFile> asts) {
    // Repeatedly scan all parsed files for imports until stable.
    var changed = true;
    while (changed) {
      changed = false;
      for (final ast in List<SourceFile>.from(asts.values)) {
        for (final imp in ast.imports) {
          if (!asts.containsKey(imp.path) && _sources.containsKey(imp.path)) {
            final unit = _registry.add(imp.path, _sources[imp.path]!);
            final impAst = _parse(unit);
            if (impAst != null) {
              asts[imp.path] = impAst;
              changed = true;
            }
          }
        }
      }
    }
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
      var yulObj = IRGenerator(_diagnostics).generateContract(contract);
      if (optimize) {
        yulObj = const YulOptimizer().optimize(yulObj);
      }
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
