/// Compiles a Solidity contract with `sol_driver` and deploys the resulting
/// bytecode with `sol_web3` — solc, web3.js, and Node.js all stay off the
/// machine.
///
/// This talks to a real JSON-RPC endpoint, so it does not run as part of
/// `melos test`. Point it at a local development chain (e.g. `anvil` or
/// `npx hardhat node`, both default to `http://127.0.0.1:8545` with
/// pre-funded accounts) and run:
///
/// ```sh
/// dart run example/full_pipeline_example.dart
/// ```
///
/// To target a different endpoint or account, set `RPC_URL` and
/// `PRIVATE_KEY` environment variables. Never put a mainnet key in shell
/// history or source control; the defaults below are Anvil/Hardhat's
/// publicly-known account #0 and are only ever safe to use on local/test
/// chains.
library;

import 'dart:io';

import 'package:sol_driver/sol_driver.dart';
import 'package:sol_web3/sol_web3.dart';

const _adderSource = '''
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

contract Adder {
    function getSum(uint256 a, uint256 b) public pure returns (uint256) {
        return a + b;
    }
}
''';

Future<void> main() async {
  final rpcUrl = Platform.environment['RPC_URL'] ?? 'http://127.0.0.1:8545';
  final privateKeyHex =
      Platform.environment['PRIVATE_KEY'] ??
      '0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80';

  print('--- 1. Compile (sol_driver) ---');
  final compilation = (CompilerStack()..addSource('Adder.sol', _adderSource))
      .compile();
  for (final diagnostic in compilation.diagnostics) {
    print(diagnostic);
  }
  if (compilation.diagnostics.any((d) => d.isError)) {
    print('compilation failed, aborting');
    return;
  }
  final bytecode = compilation.contracts['Adder']!.bytecode;
  print('compiled ${bytecode.length} bytes of init code');

  print('--- 2. Deploy (sol_web3) ---');
  final credentials = EthPrivateKey.fromHex(privateKeyHex);
  final client = EthereumClient(Uri.parse(rpcUrl));
  try {
    print('deployer address: ${credentials.address}');
    final result = await ContractDeployer(
      client,
    ).deploy(credentials: credentials, bytecode: bytecode);
    print('transaction hash: ${result.transactionHash}');
    print('contract address: ${result.contractAddress.toChecksumHex()}');
    print('gas used: ${result.receipt.gasUsed}');
  } on DeploymentException catch (e) {
    print('deployment failed: $e');
  } finally {
    client.close();
  }
}
