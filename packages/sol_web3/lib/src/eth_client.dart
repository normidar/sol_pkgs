/// Typed wrappers around the subset of `eth_*` JSON-RPC methods needed to
/// build, send, and confirm transactions.
library;

import 'dart:typed_data';

import 'codec.dart';
import 'eth_address.dart';
import 'json_rpc_client.dart';

/// A transaction receipt as returned by `eth_getTransactionReceipt`.
class TransactionReceipt {
  TransactionReceipt({
    required this.transactionHash,
    required this.status,
    required this.blockNumber,
    this.contractAddress,
    this.gasUsed,
  });

  factory TransactionReceipt.fromJson(Map<String, dynamic> json) {
    final statusHex = json['status'] as String?;
    final contractAddressHex = json['contractAddress'] as String?;
    return TransactionReceipt(
      transactionHash: json['transactionHash'] as String,
      status: statusHex == null ? null : bigIntFromHex(statusHex) == BigInt.one,
      blockNumber: bigIntFromHex(json['blockNumber'] as String),
      contractAddress: contractAddressHex == null
          ? null
          : EthAddress.fromHex(contractAddressHex),
      gasUsed: json['gasUsed'] == null
          ? null
          : bigIntFromHex(json['gasUsed'] as String),
    );
  }

  final String transactionHash;

  /// `true` if the transaction succeeded, `false` if it reverted, or `null`
  /// for pre-Byzantium chains that don't report a status.
  final bool? status;
  final BigInt blockNumber;
  final EthAddress? contractAddress;
  final BigInt? gasUsed;
}

/// A high-level Ethereum JSON-RPC client exposing the calls needed to send
/// and confirm a transaction, with results decoded into Dart types instead
/// of raw JSON hex strings.
class EthereumClient {
  EthereumClient(Uri endpoint) : _rpc = JsonRpcClient(endpoint);

  EthereumClient.withRpc(JsonRpcClient rpc) : _rpc = rpc;

  final JsonRpcClient _rpc;

  Future<BigInt> chainId() async =>
      bigIntFromHex(await _rpc.call('eth_chainId') as String);

  Future<BigInt> gasPrice() async =>
      bigIntFromHex(await _rpc.call('eth_gasPrice') as String);

  /// The suggested `maxPriorityFeePerGas` for an EIP-1559 transaction.
  Future<BigInt> maxPriorityFeePerGas() async =>
      bigIntFromHex(await _rpc.call('eth_maxPriorityFeePerGas') as String);

  Future<BigInt> getTransactionCount(
    EthAddress address, {
    String blockTag = 'pending',
  }) async => bigIntFromHex(
    await _rpc.call('eth_getTransactionCount', [address.toHex(), blockTag])
        as String,
  );

  Future<BigInt> getBalance(
    EthAddress address, {
    String blockTag = 'latest',
  }) async => bigIntFromHex(
    await _rpc.call('eth_getBalance', [address.toHex(), blockTag]) as String,
  );

  /// Estimates the gas a transaction would consume. [to] is omitted for
  /// contract-creation estimates.
  Future<BigInt> estimateGas({
    required EthAddress from,
    EthAddress? to,
    BigInt? value,
    Uint8List? data,
  }) async {
    final params = <String, String>{
      'from': from.toHex(),
      if (to != null) 'to': to.toHex(),
      if (value != null) 'value': bigIntToHex(value),
      if (data != null) 'data': bytesToHex(data, include0x: true),
    };
    return bigIntFromHex(
      await _rpc.call('eth_estimateGas', [params]) as String,
    );
  }

  /// Broadcasts a signed, RLP-encoded transaction and returns its hash.
  Future<String> sendRawTransaction(Uint8List signedTx) async =>
      await _rpc.call('eth_sendRawTransaction', [
            bytesToHex(signedTx, include0x: true),
          ])
          as String;

  /// Returns the receipt for [transactionHash], or `null` if it hasn't been
  /// mined yet.
  Future<TransactionReceipt?> getTransactionReceipt(
    String transactionHash,
  ) async {
    final result = await _rpc.call('eth_getTransactionReceipt', [
      transactionHash,
    ]);
    if (result == null) return null;
    return TransactionReceipt.fromJson(result as Map<String, dynamic>);
  }

  /// Closes the underlying HTTP connection.
  void close() => _rpc.close();
}
