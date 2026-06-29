import 'dart:convert';
import 'dart:io';
import 'package:args/args.dart';
import 'package:sol_driver/sol_driver.dart';
import 'package:sol_web3/sol_web3.dart';

/// Parses CLI arguments and runs the compiler.
///
/// Returns the process exit code (0 = success).
Future<int> runCompiler(List<String> args) async {
  final parser = ArgParser()
    ..addFlag('bin', help: 'Output EVM bytecode (hex).')
    ..addFlag('abi', help: 'Output ABI JSON.')
    ..addFlag('ir', abbr: 'y', help: 'Output Yul IR.')
    ..addFlag(
      'standard-json',
      help: 'Read standard-JSON from stdin, write to stdout.',
    )
    ..addFlag('optimize', help: 'Enable the Yul optimizer.')
    ..addMultiOption(
      'remappings',
      help: 'Import remappings (context:prefix=target).',
    )
    ..addOption('base-path', help: 'Base path for import resolution.')
    ..addMultiOption(
      'include-path',
      help: 'Additional paths to search for imports.',
    )
    ..addFlag(
      'warnings-as-errors',
      help: 'Treat warnings as compilation errors.',
    )
    ..addOption(
      'output-dir',
      abbr: 'o',
      help: 'Write output files to this directory instead of stdout.',
    )
    ..addFlag(
      'deploy',
      help: 'Deploy compiled contract to an EVM chain via JSON-RPC.',
    )
    ..addOption(
      'rpc-url',
      help:
          'JSON-RPC endpoint for deployment '
          '(env: RPC_URL, default: http://127.0.0.1:8545).',
    )
    ..addOption(
      'private-key',
      help: 'Hex-encoded private key for signing (env: PRIVATE_KEY).',
    )
    ..addOption(
      'contract',
      help:
          'Contract name to deploy when the source defines multiple contracts. '
          'Defaults to the only contract, or errors if ambiguous.',
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
  final optimize = parsed['optimize'] as bool;
  final warningsAsErrors = parsed['warnings-as-errors'] as bool;
  final outputDir = parsed['output-dir'] as String?;
  final doDeploy = parsed['deploy'] as bool;

  final stack = CompilerStack(optimize: optimize);
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

  if (!result.isSuccess(warningsAsErrors: warningsAsErrors)) return 1;

  if (outputDir != null) {
    Directory(outputDir).createSync(recursive: true);
    for (final entry in result.contracts.entries) {
      final name = entry.key;
      final out = entry.value;
      if (showBin) {
        File('$outputDir/$name.bin').writeAsStringSync(out.bytecodeHex);
      }
      if (showAbi) {
        File('$outputDir/$name.abi').writeAsStringSync(
          const JsonEncoder.withIndent('  ').convert(out.abi),
        );
      }
      if (showIr) {
        File('$outputDir/$name.yul').writeAsStringSync(out.yulIr);
      }
    }
    if (!doDeploy) return 0;
  }

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

  if (!doDeploy) return 0;

  // ── deploy mode ───────────────────────────────────────────────────────────
  final contractName = parsed['contract'] as String?;
  final ContractOutput contractOut;
  if (contractName != null) {
    if (!result.contracts.containsKey(contractName)) {
      stderr.writeln(
        'Error: contract "$contractName" not found. '
        'Available: ${result.contracts.keys.join(', ')}',
      );
      return 1;
    }
    contractOut = result.contracts[contractName]!;
  } else if (result.contracts.length == 1) {
    contractOut = result.contracts.values.first;
  } else {
    stderr.writeln(
      'Error: multiple contracts found '
      '(${result.contracts.keys.join(', ')}). '
      'Use --contract <name> to select one.',
    );
    return 1;
  }

  final rpcUrl =
      (parsed['rpc-url'] as String?) ??
      Platform.environment['RPC_URL'] ??
      'http://127.0.0.1:8545';

  final privateKeyHex =
      (parsed['private-key'] as String?) ?? Platform.environment['PRIVATE_KEY'];

  if (privateKeyHex == null) {
    stderr.writeln(
      'Error: --private-key is required for deployment '
      '(or set the PRIVATE_KEY environment variable).',
    );
    return 1;
  }

  final EthPrivateKey credentials;
  try {
    credentials = EthPrivateKey.fromHex(privateKeyHex);
  } catch (e) {
    stderr.writeln('Error: invalid private key — $e');
    return 1;
  }

  final client = EthereumClient(Uri.parse(rpcUrl));
  stdout.writeln('Deploying to $rpcUrl ...');
  stdout.writeln('Deployer: ${credentials.address}');

  try {
    final deployResult = await ContractDeployer(
      client,
    ).deploy(credentials: credentials, bytecode: contractOut.bytecode);
    _printDeploySuccess(
      contractName: contractOut.name,
      address: deployResult.contractAddress.toChecksumHex(),
      txHash: deployResult.transactionHash,
      gasUsed: deployResult.receipt.gasUsed,
      abi: contractOut.abi,
    );
    return 0;
  } on DeploymentException catch (e) {
    stderr.writeln('Deployment failed: $e');
    return 1;
  } finally {
    client.close();
  }
}

void _printDeploySuccess({
  required String contractName,
  required String address,
  required String txHash,
  required BigInt? gasUsed,
  required List<Map<String, dynamic>> abi,
}) {
  final sep = '─' * 60;
  stdout.writeln('\n$sep');
  stdout.writeln('  Deployed: $contractName');
  stdout.writeln(sep);
  stdout.writeln('  Address  : $address');
  stdout.writeln('  Tx hash  : $txHash');
  stdout.writeln('  Gas used : $gasUsed');

  final fns =
      abi
          .where(
            (e) =>
                e['type'] == 'function' &&
                _isPublic(e['stateMutability'] as String? ?? ''),
          )
          .toList();

  if (fns.isNotEmpty) {
    stdout.writeln('\n  Public functions:');
    for (final fn in fns) {
      stdout.writeln('    ${_formatFn(fn)}');
    }
  }

  final events =
      abi.where((e) => e['type'] == 'event').toList();
  if (events.isNotEmpty) {
    stdout.writeln('\n  Events:');
    for (final ev in events) {
      final name = ev['name'] as String;
      final inputs = _formatParams(
        ev['inputs'] as List<dynamic>? ?? [],
      );
      stdout.writeln('    $name($inputs)');
    }
  }

  stdout.writeln(sep);
}

bool _isPublic(String mutability) => true;

String _formatFn(Map<String, dynamic> fn) {
  final name = fn['name'] as String;
  final inputs = _formatParams(fn['inputs'] as List<dynamic>? ?? []);
  final outputs = fn['outputs'] as List<dynamic>? ?? [];
  final mutability = fn['stateMutability'] as String? ?? '';

  final outputStr =
      outputs.isEmpty
          ? ''
          : ' → ${_formatParams(outputs, namesOptional: true)}';

  final tag = switch (mutability) {
    'pure' => ' [pure]',
    'view' => ' [view]',
    'payable' => ' [payable]',
    _ => '',
  };

  return '$name($inputs)$outputStr$tag';
}

String _formatParams(
  List<dynamic> params, {
  bool namesOptional = false,
}) {
  return params.map((p) {
    final m = p as Map<String, dynamic>;
    final type = m['type'] as String? ?? '';
    final name = m['name'] as String? ?? '';
    if (namesOptional || name.isEmpty) return type;
    return '$type $name';
  }).join(', ');
}
