import 'dart:convert';
import 'dart:io';
import 'package:args/args.dart';
import 'package:sol_driver/sol_driver.dart';

/// Parses CLI arguments and runs the compiler.
///
/// Returns the process exit code (0 = success).
int runCompiler(List<String> args) {
  final parser = ArgParser()
    ..addFlag('bin', help: 'Output EVM bytecode (hex).')
    ..addFlag('abi', help: 'Output ABI JSON.')
    ..addFlag('ir', abbr: 'y', help: 'Output Yul IR.')
    ..addFlag(
      'standard-json',
      help: 'Read standard-JSON from stdin, write to stdout.',
    )
    ..addFlag('optimize', help: 'Enable Yul optimizer (not yet implemented).')
    ..addMultiOption(
      'remappings',
      help: 'Import remappings (context:prefix=target).',
    )
    ..addOption('base-path', help: 'Base path for import resolution.')
    ..addMultiOption(
      'include-path',
      help: 'Additional paths to search for imports.',
    )
    ..addFlag('version', negatable: false, help: 'Print version and exit.')
    ..addFlag('help', abbr: 'h', negatable: false, help: 'Show usage.');

  late ArgResults parsed;
  try {
    parsed = parser.parse(args);
  } catch (e) {
    stderr.writeln('Error: $e');
    stderr.writeln(parser.usage);
    return 1;
  }

  if (parsed['help'] as bool) {
    stdout.writeln('solc-dart — Solidity compiler (pure Dart)\n');
    stdout.writeln(parser.usage);
    return 0;
  }

  if (parsed['version'] as bool) {
    stdout.writeln('solc-dart 0.1.0');
    return 0;
  }

  // ── standard-JSON mode ────────────────────────────────────────────────────
  if (parsed['standard-json'] as bool) {
    final input = stdin.readLineSync(encoding: utf8) ?? '';
    stdout.write(StandardJson().compile(input));
    return 0;
  }

  // ── file mode ─────────────────────────────────────────────────────────────
  final files = parsed.rest;
  if (files.isEmpty) {
    stderr.writeln('No input files. Use --help for usage.');
    return 1;
  }

  final showBin = parsed['bin'] as bool;
  final showAbi = parsed['abi'] as bool;
  final showIr = parsed['ir'] as bool;

  final stack = CompilerStack();
  for (final path in files) {
    final file = File(path);
    if (!file.existsSync()) {
      stderr.writeln('Error: file not found: $path');
      return 1;
    }
    stack.addSource(path, file.readAsStringSync());
  }

  final result = stack.compile();

  for (final d in result.diagnostics) {
    (d.isError ? stderr : stdout).writeln(d);
  }

  if (!result.success) return 1;

  for (final entry in result.contracts.entries) {
    final name = entry.key;
    final out = entry.value;

    if (showBin) {
      stdout.writeln('======= $name =======');
      stdout.writeln('Binary:');
      stdout.writeln(out.bytecodeHex);
    }
    if (showAbi) {
      stdout.writeln('======= $name =======');
      stdout.writeln('Contract JSON ABI:');
      stdout.writeln(const JsonEncoder.withIndent('  ').convert(out.abi));
    }
    if (showIr) {
      stdout.writeln('======= $name =======');
      stdout.writeln('IR:');
      stdout.writeln(out.yulIr);
    }
  }

  return 0;
}
