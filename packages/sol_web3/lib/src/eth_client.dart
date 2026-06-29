/// Typed wrappers around the subset of `eth_*` JSON-RPC methods needed to
/// build, send, and confirm transactions.
library;

import 'dart:typed_data';

import 'codec.dart';
import 'eth_address.dart';
import 'json_rpc_client.dart';
import 'json_rpc_transport.dart';
import 'websocket_json_rpc_client.dart';

// ── Log / event types ─────────────────────────────────────────────────────────

/// A filter used to select event logs from `eth_getLogs`.
///
/// All fields are optional; omitting them returns all logs.
class LogFilter {
  const LogFilter({
    this.address,
    this.topics,
    this.fromBlock = 'latest',
    this.toBlock = 'latest',
    this.blockHash,
  });

  /// Contract address to filter by (or null to include all contracts).
  final EthAddress? address;

  /// Topic filters: each element is a topic hash (or null to match any value
  /// in that position).  Topics are AND-ed; within a list OR-ed.
  final List<String?>? topics;

  final String fromBlock;
  final String toBlock;

  /// Mutually exclusive with [fromBlock]/[toBlock].
  final String? blockHash;

  Map<String, Object?> toJson() => {
    if (address != null) 'address': address!.toHex(),
    if (topics != null) 'topics': topics,
    if (blockHash != null) 'blockHash': blockHash,
    if (blockHash == null) 'fromBlock': fromBlock,
    if (blockHash == null) 'toBlock': toBlock,
  };
}

/// A single event log entry as returned by `eth_getLogs` or
/// `eth_getTransactionReceipt`.
class EventLog {
  EventLog({
    required this.address,
    required this.topics,
    required this.data,
    required this.blockNumber,
    required this.transactionHash,
    required this.transactionIndex,
    required this.blockHash,
    required this.logIndex,
    required this.removed,
  });

  factory EventLog.fromJson(Map<String, dynamic> json) {
    final topicsList = (json['topics'] as List).cast<String>();
    final dataHex = json['data'] as String? ?? '0x';
    final data = dataHex.length > 2
        ? hexToBytes(dataHex.substring(2))
        : Uint8List(0);
    return EventLog(
      address: EthAddress.fromHex(json['address'] as String),
      topics: topicsList,
      data: data,
      blockNumber: bigIntFromHex(json['blockNumber'] as String),
      transactionHash: json['transactionHash'] as String,
      transactionIndex: bigIntFromHex(
        json['transactionIndex'] as String,
      ).toInt(),
      blockHash: json['blockHash'] as String,
      logIndex: bigIntFromHex(json['logIndex'] as String).toInt(),
      removed: json['removed'] as bool? ?? false,
    );
  }

  /// The address of the contract that emitted this log.
  final EthAddress address;

  /// The topics (topic[0] = event signature hash for non-anonymous events).
  final List<String> topics;

  /// The ABI-encoded non-indexed event data.
  final Uint8List data;

  final BigInt blockNumber;
  final String transactionHash;
  final int transactionIndex;
  final String blockHash;
  final int logIndex;

  /// `true` when the log was emitted in a block that was later orphaned.
  final bool removed;

  @override
  String toString() =>
      'EventLog(address: $address, topics: $topics, '
      'block: $blockNumber, txIndex: $transactionIndex)';
}

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

  EthereumClient.withRpc(JsonRpcTransport rpc) : _rpc = rpc;

  final JsonRpcTransport _rpc;

  /// The underlying JSON-RPC transport. Useful when you need lower-level
  /// access — e.g. to call [WebSocketJsonRpcClient.subscribe] on a
  /// WebSocket-backed client.
  JsonRpcTransport get transport => _rpc;

  /// Subscribes to `newHeads` (one event per new block header).
  ///
  /// Requires the underlying transport to be a [WebSocketJsonRpcClient].
  Future<({String id, Stream<Map<String, dynamic>> events})>
  subscribeNewHeads() => _ws().subscribe('newHeads');

  /// Subscribes to `logs` matching [filter].
  ///
  /// Requires the underlying transport to be a [WebSocketJsonRpcClient].
  Future<({String id, Stream<Map<String, dynamic>> events})> subscribeLogs(
    LogFilter filter,
  ) => _ws().subscribe('logs', filter.toJson());

  /// Cancels a previously created subscription.
  Future<bool> unsubscribe(String subscriptionId) =>
      _ws().unsubscribe(subscriptionId);

  WebSocketJsonRpcClient _ws() {
    final t = _rpc;
    if (t is! WebSocketJsonRpcClient) {
      throw StateError(
        'eth_subscribe requires a WebSocketJsonRpcClient transport',
      );
    }
    return t;
  }

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

  /// Returns all event logs matching [filter].
  ///
  /// Calls `eth_getLogs` and decodes each entry into an [EventLog].
  Future<List<EventLog>> getLogs(LogFilter filter) async {
    final result = await _rpc.call('eth_getLogs', [filter.toJson()]);
    final list = result as List;
    return list
        .map((e) => EventLog.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// Executes a read-only call against [to] with [data] and returns the raw
  /// return bytes. Uses the given [blockTag] (default `'latest'`).
  Future<Uint8List> ethCall({
    required EthAddress to,
    required Uint8List data,
    EthAddress? from,
    String blockTag = 'latest',
  }) async {
    final params = <String, dynamic>{
      'to': to.toHex(),
      'data': bytesToHex(data, include0x: true),
      if (from != null) 'from': from.toHex(),
    };
    final hex = await _rpc.call('eth_call', [params, blockTag]) as String;
    final clean = hex.startsWith('0x') ? hex.substring(2) : hex;
    if (clean.isEmpty) return Uint8List(0);
    final bytes = Uint8List(clean.length ~/ 2);
    for (var i = 0; i < bytes.length; i++) {
      bytes[i] = int.parse(clean.substring(i * 2, i * 2 + 2), radix: 16);
    }
    return bytes;
  }

  /// Closes the underlying connection (HTTP client or WebSocket).
  Future<void> close() async => _rpc.close();
}
