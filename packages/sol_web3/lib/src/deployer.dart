/// High-level contract deployment: turns compiled init-code bytecode into a
/// signed, broadcast, and confirmed transaction.
library;

import 'dart:async';
import 'dart:typed_data';

import 'package:sol_support/sol_support.dart';

import 'crypto/eth_private_key.dart';
import 'eth_address.dart';
import 'eth_client.dart';
import 'rlp.dart';
import 'transaction.dart';

/// Thrown when a deployment fails outright (send error) or mines with a
/// reverted (failure) status.
class DeploymentException implements Exception {
  DeploymentException(this.message);

  final String message;

  @override
  String toString() => 'DeploymentException: $message';
}

/// The outcome of a successful contract deployment.
class DeploymentResult {
  DeploymentResult({
    required this.contractAddress,
    required this.transactionHash,
    required this.receipt,
  });

  final EthAddress contractAddress;
  final String transactionHash;
  final TransactionReceipt receipt;
}

/// Derives the address a `CREATE` (not `CREATE2`) deployment from [sender]
/// at [nonce] will receive: the low 20 bytes of `keccak256(rlp([sender,
/// nonce]))`.
EthAddress computeCreateAddress(EthAddress sender, BigInt nonce) {
  final encoded = rlpEncode(RlpList([RlpBytes(sender.bytes), rlpUint(nonce)]));
  return EthAddress(keccak256(encoded).sublist(12));
}

/// Orchestrates a contract deployment: fetches nonce and fee data, estimates
/// gas, builds and signs the transaction, broadcasts it, and polls for the
/// receipt.
class ContractDeployer {
  ContractDeployer(this.client);

  final EthereumClient client;

  /// Deploys [bytecode] (contract creation code, already including
  /// constructor-argument ABI encoding if any) signed by [credentials].
  ///
  /// [value] is the wei sent with the creation transaction (default zero).
  /// [gasLimit], [chainId] are fetched/estimated automatically when not
  /// supplied. Polls for the receipt every [pollInterval] up to [timeout],
  /// throwing [DeploymentException] on revert or timeout.
  Future<DeploymentResult> deploy({
    required EthPrivateKey credentials,
    required Uint8List bytecode,
    BigInt? value,
    BigInt? gasLimit,
    BigInt? chainId,
    TransactionType type = TransactionType.eip1559,
    Duration pollInterval = const Duration(seconds: 1),
    Duration timeout = const Duration(minutes: 2),
  }) async {
    final sender = credentials.address;
    final resolvedChainId = chainId ?? await client.chainId();
    final nonce = await client.getTransactionCount(sender);
    final resolvedGasLimit =
        gasLimit ??
        (await client.estimateGas(from: sender, data: bytecode) *
                BigInt.from(12)) ~/
            BigInt.from(10);

    BigInt gasPrice = BigInt.zero;
    BigInt maxPriorityFeePerGas = BigInt.zero;
    BigInt maxFeePerGas = BigInt.zero;
    if (type == TransactionType.legacy) {
      gasPrice = await client.gasPrice();
    } else {
      maxPriorityFeePerGas = await client.maxPriorityFeePerGas();
      final baseFeeEstimate = await client.gasPrice();
      maxFeePerGas = baseFeeEstimate + maxPriorityFeePerGas;
    }

    final tx = EthereumTransaction(
      chainId: resolvedChainId,
      nonce: nonce,
      gasLimit: resolvedGasLimit,
      data: bytecode,
      value: value,
      type: type,
      gasPrice: gasPrice,
      maxPriorityFeePerGas: maxPriorityFeePerGas,
      maxFeePerGas: maxFeePerGas,
    );

    final signed = tx.sign(credentials);
    final txHash = await client.sendRawTransaction(signed);

    final receipt = await _pollForReceipt(txHash, pollInterval, timeout);
    if (receipt.status == false) {
      throw DeploymentException('deployment transaction $txHash reverted');
    }
    final contractAddress =
        receipt.contractAddress ?? computeCreateAddress(sender, nonce);
    return DeploymentResult(
      contractAddress: contractAddress,
      transactionHash: txHash,
      receipt: receipt,
    );
  }

  Future<TransactionReceipt> _pollForReceipt(
    String txHash,
    Duration pollInterval,
    Duration timeout,
  ) async {
    final deadline = DateTime.now().add(timeout);
    while (true) {
      final receipt = await client.getTransactionReceipt(txHash);
      if (receipt != null) return receipt;
      if (DateTime.now().isAfter(deadline)) {
        throw DeploymentException(
          'timed out waiting for receipt of $txHash after $timeout',
        );
      }
      await Future<void>.delayed(pollInterval);
    }
  }
}
