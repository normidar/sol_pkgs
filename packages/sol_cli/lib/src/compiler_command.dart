import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:args/args.dart';
import 'package:sol_abi/sol_abi.dart';
import 'package:sol_driver/sol_driver.dart';
import 'package:sol_types/sol_types.dart';
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
    ..addOption(
      'call',
      help:
          'Call a deployed contract function. '
          'Format: ContractName.functionName(arg1,arg2,...)\n'
          'Reads address and ABI from deployments.json in the current directory.\n'
          'view/pure functions use eth_call; others sign and send a transaction.',
    )
    ..addOption(
      'info',
      help:
          'Show stored deployment info for a contract by name.\n'
          'Reads from deployments.json in the current directory.\n'
          'Example: --info Counter',
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

  // ── info mode ─────────────────────────────────────────────────────────────
  final infoName = parsed['info'] as String?;
  if (infoName != null) {
    return _runInfo(infoName);
  }

  // ── call mode ─────────────────────────────────────────────────────────────
  final callExpr = parsed['call'] as String?;
  if (callExpr != null) {
    final rpcUrl =
        (parsed['rpc-url'] as String?) ??
        Platform.environment['RPC_URL'] ??
        'http://127.0.0.1:8545';
    final privateKeyHex =
        (parsed['private-key'] as String?) ??
        Platform.environment['PRIVATE_KEY'];
    return _runCall(callExpr, rpcUrl: rpcUrl, privateKeyHex: privateKeyHex);
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
    final chainId = await client.chainId();
    final deployResult = await ContractDeployer(
      client,
    ).deploy(credentials: credentials, bytecode: contractOut.bytecode);

    final address = deployResult.contractAddress.toChecksumHex();
    _printDeploySuccess(
      contractName: contractOut.name,
      address: address,
      txHash: deployResult.transactionHash,
      gasUsed: deployResult.receipt.gasUsed,
      abi: contractOut.abi,
    );

    final recordFile = _saveDeployment(
      name: contractOut.name,
      address: address,
      chainId: chainId,
      txHash: deployResult.transactionHash,
      rpcUrl: rpcUrl,
      abi: contractOut.abi,
    );
    stdout.writeln('  Record saved → $recordFile');

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

  final fns = abi
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

  final events = abi.where((e) => e['type'] == 'event').toList();
  if (events.isNotEmpty) {
    stdout.writeln('\n  Events:');
    for (final ev in events) {
      final name = ev['name'] as String;
      final inputs = _formatParams(ev['inputs'] as List<dynamic>? ?? []);
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

  final outputStr = outputs.isEmpty
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

String _formatParams(List<dynamic> params, {bool namesOptional = false}) {
  return params
      .map((p) {
        final m = p as Map<String, dynamic>;
        final type = m['type'] as String? ?? '';
        final name = m['name'] as String? ?? '';
        if (namesOptional || name.isEmpty) return type;
        return '$type $name';
      })
      .join(', ');
}

/// Appends a deployment record to [deployments.json] in the current directory.
///
/// Returns the path of the record file.
String _saveDeployment({
  required String name,
  required String address,
  required BigInt chainId,
  required String txHash,
  required String rpcUrl,
  required List<Map<String, dynamic>> abi,
}) {
  const fileName = 'deployments.json';
  final file = File(fileName);

  List<dynamic> records = [];
  if (file.existsSync()) {
    try {
      records = jsonDecode(file.readAsStringSync()) as List<dynamic>;
    } catch (_) {
      records = [];
    }
  }

  records.add({
    'name': name,
    'address': address,
    'chainId': chainId.toInt(),
    'txHash': txHash,
    'rpcUrl': rpcUrl,
    'deployedAt': DateTime.now().toUtc().toIso8601String(),
    'abi': abi,
  });

  file.writeAsStringSync(const JsonEncoder.withIndent('  ').convert(records));

  return file.absolute.path;
}

// ── info command ─────────────────────────────────────────────────────────────

int _runInfo(String contractName) {
  final depFile = File('deployments.json');
  if (!depFile.existsSync()) {
    stderr.writeln(
      'Error: deployments.json not found in current directory.\n'
      'Deploy a contract first with: solc --deploy <file.sol>',
    );
    return 1;
  }

  final records = (jsonDecode(depFile.readAsStringSync()) as List)
      .cast<Map<String, dynamic>>();

  final matches = records.where((r) => r['name'] == contractName).toList();

  if (matches.isEmpty) {
    final names = records.map((r) => r['name']).toSet().join(', ');
    stderr.writeln(
      'Error: contract "$contractName" not found in deployments.json.\n'
      'Available: $names',
    );
    return 1;
  }

  final sep = '─' * 60;

  for (var i = 0; i < matches.length; i++) {
    final r = matches[i];
    final abi = (r['abi'] as List? ?? []).cast<Map<String, dynamic>>();

    stdout.writeln('\n$sep');
    if (matches.length > 1) {
      stdout.writeln('  Deployment ${i + 1} of ${matches.length}');
    }
    stdout.writeln('  Contract : ${r['name']}');
    stdout.writeln(sep);
    stdout.writeln('  Address  : ${r['address']}');
    stdout.writeln('  Chain ID : ${r['chainId']}');
    stdout.writeln('  Tx hash  : ${r['txHash']}');
    stdout.writeln('  RPC URL  : ${r['rpcUrl']}');
    stdout.writeln('  Deployed : ${r['deployedAt']}');

    final fns = abi.where((e) => e['type'] == 'function').toList();
    if (fns.isNotEmpty) {
      stdout.writeln('\n  Public functions:');
      for (final fn in fns) {
        stdout.writeln('    ${_formatFn(fn)}');
      }
    }

    final events = abi.where((e) => e['type'] == 'event').toList();
    if (events.isNotEmpty) {
      stdout.writeln('\n  Events:');
      for (final ev in events) {
        final name = ev['name'] as String;
        final inputs = _formatParams(ev['inputs'] as List<dynamic>? ?? []);
        stdout.writeln('    $name($inputs)');
      }
    }

    stdout.writeln(sep);
  }

  return 0;
}

// ── call command ─────────────────────────────────────────────────────────────

Future<int> _runCall(
  String expr, {
  required String rpcUrl,
  required String? privateKeyHex,
}) async {
  // Parse "ContractName.fnName(arg1,arg2,...)"
  final match = RegExp(
    r'^([A-Za-z_]\w*)\.([A-Za-z_]\w*)\((.*)\)$',
    dotAll: true,
  ).firstMatch(expr.trim());
  if (match == null) {
    stderr.writeln(
      'Error: invalid call expression "$expr".\n'
      'Expected format: ContractName.functionName(arg1,arg2,...)',
    );
    return 1;
  }
  final contractName = match.group(1)!;
  final fnName = match.group(2)!;
  final rawArgs = match.group(3)!.trim();

  // Load deployments.json
  final depFile = File('deployments.json');
  if (!depFile.existsSync()) {
    stderr.writeln(
      'Error: deployments.json not found in current directory.\n'
      'Deploy a contract first with: solc --deploy <file.sol>',
    );
    return 1;
  }
  final records = (jsonDecode(depFile.readAsStringSync()) as List)
      .cast<Map<String, dynamic>>();
  final record = records.lastWhere(
    (r) => r['name'] == contractName,
    orElse: () => {},
  );
  if (record.isEmpty) {
    stderr.writeln(
      'Error: contract "$contractName" not found in deployments.json.\n'
      'Available: ${records.map((r) => r['name']).toSet().join(', ')}',
    );
    return 1;
  }

  final address = EthAddress.fromHex(record['address'] as String);
  final abi = (record['abi'] as List).cast<Map<String, dynamic>>();

  // Find matching function in ABI
  final fnDef = abi.firstWhere(
    (e) => e['type'] == 'function' && e['name'] == fnName,
    orElse: () => {},
  );
  if (fnDef.isEmpty) {
    final fns = abi
        .where((e) => e['type'] == 'function')
        .map((e) => e['name'])
        .join(', ');
    stderr.writeln(
      'Error: function "$fnName" not found in $contractName ABI.\n'
      'Available functions: $fns',
    );
    return 1;
  }

  final inputs = (fnDef['inputs'] as List? ?? []).cast<Map<String, dynamic>>();
  final outputs = (fnDef['outputs'] as List? ?? [])
      .cast<Map<String, dynamic>>();
  final mutability = fnDef['stateMutability'] as String? ?? 'nonpayable';

  // Parse and encode arguments
  final argStrings = rawArgs.isEmpty ? <String>[] : _splitArgs(rawArgs);
  if (argStrings.length != inputs.length) {
    stderr.writeln(
      'Error: $fnName expects ${inputs.length} argument(s), '
      'got ${argStrings.length}.',
    );
    return 1;
  }

  final List<(SolType, Object?)> encodedArgs;
  try {
    encodedArgs = [
      for (var i = 0; i < inputs.length; i++)
        (
          _parseSolType(inputs[i]['type'] as String),
          _parseArgValue(argStrings[i], inputs[i]['type'] as String),
        ),
    ];
  } catch (e) {
    stderr.writeln('Error encoding arguments: $e');
    return 1;
  }

  // Build calldata = 4-byte selector + ABI-encoded args
  final signature = '$fnName(${inputs.map((p) => p['type']).join(',')})';
  final selector = selectorBytes(signature);
  final encoded = AbiEncoder().encode(encodedArgs);
  final calldata = Uint8List(selector.length + encoded.length)
    ..setAll(0, selector)
    ..setAll(selector.length, encoded);

  final client = EthereumClient(Uri.parse(rpcUrl));
  try {
    if (mutability == 'view' || mutability == 'pure') {
      // Read-only: eth_call
      final result = await client.ethCall(to: address, data: calldata);
      final outputTypes = outputs
          .map((o) => _parseSolType(o['type'] as String))
          .toList();
      _printCallResult(
        fnName: fnName,
        signature: signature,
        mutability: mutability,
        rawHex: result,
        outputs: outputs,
        outputTypes: outputTypes,
      );
    } else {
      // State-changing: sign and send tx
      if (privateKeyHex == null) {
        stderr.writeln(
          'Error: --private-key is required to call a non-view function '
          '(or set PRIVATE_KEY env var).',
        );
        return 1;
      }
      final credentials = EthPrivateKey.fromHex(privateKeyHex);
      final chainId = await client.chainId();
      final nonce = await client.getTransactionCount(credentials.address);
      final gasPrice = await client.gasPrice();
      final gasLimit = await client.estimateGas(
        to: address,
        data: calldata,
        from: credentials.address,
      );

      final tx = EthereumTransaction(
        type: TransactionType.eip1559,
        chainId: chainId,
        nonce: nonce,
        maxFeePerGas: gasPrice,
        maxPriorityFeePerGas: BigInt.from(1000000000),
        gasLimit: gasLimit * BigInt.from(120) ~/ BigInt.from(100),
        to: address,
        data: calldata,
      );
      final signed = tx.sign(credentials);
      final txHash = await client.sendRawTransaction(signed);

      final sep = '─' * 60;
      stdout.writeln('\n$sep');
      stdout.writeln('  Called: $contractName.$signature');
      stdout.writeln(sep);
      stdout.writeln('  Tx hash : $txHash');
      stdout.writeln('  Status  : pending (state-changing call)');
      stdout.writeln(sep);
    }
    return 0;
  } catch (e) {
    stderr.writeln('Call failed: $e');
    return 1;
  } finally {
    client.close();
  }
}

void _printCallResult({
  required String fnName,
  required String signature,
  required String mutability,
  required Uint8List rawHex,
  required List<Map<String, dynamic>> outputs,
  required List<SolType> outputTypes,
}) {
  final sep = '─' * 60;
  stdout.writeln('\n$sep');
  stdout.writeln('  Result: $signature  [$mutability]');
  stdout.writeln(sep);
  if (rawHex.isEmpty || outputs.isEmpty) {
    stdout.writeln('  (no return value)');
  } else {
    final values = AbiDecoder().decode(outputTypes, rawHex);
    for (var i = 0; i < outputs.length; i++) {
      final name = outputs[i]['name'] as String? ?? '';
      final type = outputs[i]['type'] as String? ?? '';
      final label = name.isNotEmpty ? '$type $name' : type;
      stdout.writeln('  $label = ${_formatValue(values[i], outputTypes[i])}');
    }
  }
  stdout.writeln(sep);
}

String _formatValue(Object? value, SolType type) {
  if (value is BigInt) {
    if (type is AddressType) {
      final hex = value.toRadixString(16).padLeft(40, '0');
      return '0x$hex';
    }
    return value.toString();
  }
  if (value is bool) return value.toString();
  if (value is String) return '"$value"';
  if (value is Uint8List) {
    return '0x${value.map((b) => b.toRadixString(16).padLeft(2, '0')).join()}';
  }
  if (value is List)
    return '[${value.map((v) => _formatValue(v, type)).join(', ')}]';
  return '$value';
}

/// Splits `"arg1,arg2,arg3"` respecting nested parentheses and quotes.
List<String> _splitArgs(String raw) {
  final result = <String>[];
  var depth = 0;
  var inString = false;
  final current = StringBuffer();
  for (var i = 0; i < raw.length; i++) {
    final c = raw[i];
    if (c == '"' && (i == 0 || raw[i - 1] != r'\')) {
      inString = !inString;
      current.write(c);
    } else if (!inString && c == '(') {
      depth++;
      current.write(c);
    } else if (!inString && c == ')') {
      depth--;
      current.write(c);
    } else if (!inString && depth == 0 && c == ',') {
      result.add(current.toString().trim());
      current.clear();
    } else {
      current.write(c);
    }
  }
  if (current.isNotEmpty) result.add(current.toString().trim());
  return result;
}

/// Parses an ABI type string (e.g. `"uint256"`, `"address"`, `"bool"`,
/// `"bytes32"`, `"string"`, `"uint256[]"`) into a [SolType].
SolType _parseSolType(String type) {
  // Strip trailing [] or [N] for arrays
  if (type.endsWith(']')) {
    final bracketOpen = type.lastIndexOf('[');
    final inner = type.substring(0, bracketOpen);
    final sizeStr = type.substring(bracketOpen + 1, type.length - 1);
    final elementType = _parseSolType(inner);
    final size = sizeStr.isEmpty ? null : int.tryParse(sizeStr);
    return ArrayType(elementType, length: size);
  }
  if (type == 'address' || type == 'address payable')
    return const AddressType();
  if (type == 'bool') return const BoolType();
  if (type == 'string') return const StringType();
  if (type == 'bytes') return const BytesType();
  if (type.startsWith('bytes') && type.length > 5) {
    final n = int.tryParse(type.substring(5));
    if (n != null) return BytesNType(n);
  }
  if (type.startsWith('uint')) {
    final bits = int.tryParse(type.substring(4)) ?? 256;
    return IntType(bits, signed: false);
  }
  if (type.startsWith('int')) {
    final bits = int.tryParse(type.substring(3)) ?? 256;
    return IntType(bits, signed: true);
  }
  throw ArgumentError('Unsupported ABI type: $type');
}

/// Converts a CLI argument string to a Dart value compatible with [SolType].
Object? _parseArgValue(String raw, String abiType) {
  final trimmed = raw.trim();
  if (abiType == 'bool') {
    if (trimmed == 'true') return true;
    if (trimmed == 'false') return false;
    throw ArgumentError('Expected true/false for bool, got "$trimmed"');
  }
  if (abiType == 'string') {
    if (trimmed.startsWith('"') && trimmed.endsWith('"')) {
      return trimmed.substring(1, trimmed.length - 1);
    }
    return trimmed;
  }
  if (abiType == 'address' || abiType == 'address payable') {
    return trimmed.startsWith('0x')
        ? BigInt.parse(trimmed.substring(2), radix: 16)
        : BigInt.parse(trimmed);
  }
  if (abiType.startsWith('uint') || abiType.startsWith('int')) {
    if (trimmed.startsWith('0x')) {
      return BigInt.parse(trimmed.substring(2), radix: 16);
    }
    return BigInt.parse(trimmed);
  }
  if (abiType == 'bytes' || RegExp(r'^bytes\d+$').hasMatch(abiType)) {
    return trimmed;
  }
  return trimmed;
}
