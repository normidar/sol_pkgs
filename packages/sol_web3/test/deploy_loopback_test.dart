/// End-to-end exercise of the deployment pipeline against a local
/// `dart:io HttpServer` standing in for a real Ethereum JSON-RPC node — no
/// network access required, but every byte that would cross the wire to a
/// real node (the signed raw transaction) is produced for real and
/// independently re-validated by the mock server below.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:sol_driver/sol_driver.dart';
import 'package:sol_support/sol_support.dart';
import 'package:sol_web3/sol_web3.dart';
import 'package:test/test.dart';

const _adderSource = '''
pragma solidity ^0.8.0;
contract Adder {
  function getSum(uint256 a, uint256 b) public pure returns (uint256) {
    return a + b;
  }
}
''';

/// A fake Ethereum node that understands just enough JSON-RPC to let
/// [ContractDeployer.deploy] run to completion, while independently
/// re-deriving the sender from the raw transaction's signature so the test
/// fails if the signing/encoding pipeline ever produces an unverifiable tx.
class _FakeEthNode {
  _FakeEthNode(this.server, {this.revertTransactions = false}) {
    server.listen(_handle);
  }

  static Future<_FakeEthNode> start({bool revertTransactions = false}) async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    return _FakeEthNode(server, revertTransactions: revertTransactions);
  }

  final HttpServer server;

  /// When true, every mined transaction's receipt reports a failure status,
  /// so [ContractDeployer.deploy] should surface a [DeploymentException].
  final bool revertTransactions;
  final Map<String, Map<String, Object?>> _receipts = {};
  final Map<String, int> _receiptPollCount = {};
  EthAddress? recoveredSender;
  BigInt? observedNonce;

  Uri get uri => Uri.parse('http://127.0.0.1:${server.port}');

  Future<void> _handle(HttpRequest request) async {
    final body = await utf8.decoder.bind(request).join();
    final decoded = jsonDecode(body) as Map<String, dynamic>;
    final method = decoded['method'] as String;
    final params = (decoded['params'] as List).cast<Object?>();

    Object? result;
    switch (method) {
      case 'eth_chainId':
        result = '0x7a69'; // 31337, Hardhat's default chain id.
      case 'eth_getTransactionCount':
        result = '0x0';
      case 'eth_gasPrice':
        result = '0x3b9aca00'; // 1 gwei.
      case 'eth_maxPriorityFeePerGas':
        result = '0x3b9aca00';
      case 'eth_estimateGas':
        result = '0x186a0'; // 100000.
      case 'eth_sendRawTransaction':
        result = _handleSendRawTransaction(params[0] as String);
      case 'eth_getTransactionReceipt':
        result = _handleGetReceipt(params[0] as String);
      default:
        throw StateError('unexpected JSON-RPC method in test: $method');
    }

    request.response.headers.contentType = ContentType.json;
    request.response.write(
      jsonEncode({'jsonrpc': '2.0', 'id': decoded['id'], 'result': result}),
    );
    await request.response.close();
  }

  String _handleSendRawTransaction(String rawHex) {
    final raw = hexToBytes(rawHex);
    if (raw[0] != 0x02) {
      throw StateError(
        'expected an EIP-1559 (type 2) transaction, got type ${raw[0]}',
      );
    }
    final decoded = rlpDecode(raw.sublist(1)) as RlpList;
    final items = decoded.items;
    if (items.length != 12) {
      throw StateError(
        'expected 12 RLP fields in an EIP-1559 payload, got ${items.length}',
      );
    }

    final nonce = bytesToBigInt((items[1] as RlpBytes).data);
    final v = bytesToBigInt((items[9] as RlpBytes).data);
    final r = bytesToBigInt((items[10] as RlpBytes).data);
    final s = bytesToBigInt((items[11] as RlpBytes).data);

    final unsignedPayload = Uint8List.fromList([
      0x02,
      ...rlpEncode(RlpList(items.sublist(0, 9))),
    ]);
    final hash = keccak256(unsignedPayload);
    final sig = EcdsaSignature(r, s, v.toInt());
    final sender = recoverEthAddress(sig, hash);
    if (sender == null) {
      throw StateError(
        'raw transaction signature did not recover to a valid address',
      );
    }
    recoveredSender = sender;
    observedNonce = nonce;

    final txHash = bytesToHex(keccak256(raw), include0x: true);
    _receipts[txHash] = {
      'transactionHash': txHash,
      'status': revertTransactions ? '0x0' : '0x1',
      'blockNumber': '0x1',
      'gasUsed': '0x5208',
      'contractAddress': computeCreateAddress(sender, nonce).toHex(),
    };
    return txHash;
  }

  Map<String, Object?>? _handleGetReceipt(String txHash) {
    // Simulate a transaction that takes one extra poll to be mined, so the
    // deployer's polling loop is genuinely exercised rather than succeeding
    // on the very first request.
    final pollCount = (_receiptPollCount[txHash] ?? 0) + 1;
    _receiptPollCount[txHash] = pollCount;
    if (pollCount < 2) return null;
    return _receipts[txHash];
  }

  Future<void> close() => server.close(force: true);
}

void main() {
  test(
    'compiled bytecode deploys end-to-end against a local mock node',
    () async {
      final stack = CompilerStack()..addSource('Adder.sol', _adderSource);
      final compilation = stack.compile();
      expect(compilation.diagnostics.where((d) => d.isError), isEmpty);
      final bytecode = compilation.contracts['Adder']!.bytecode;
      expect(bytecode, isNotEmpty);

      final node = await _FakeEthNode.start();
      final key = EthPrivateKey.fromHex(
        '0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80',
      );
      final client = EthereumClient(node.uri);
      final deployer = ContractDeployer(client);

      try {
        final result = await deployer.deploy(
          credentials: key,
          bytecode: bytecode,
          pollInterval: const Duration(milliseconds: 10),
          timeout: const Duration(seconds: 5),
        );

        expect(node.recoveredSender, key.address);
        expect(node.observedNonce, BigInt.zero);
        expect(result.receipt.status, isTrue);
        expect(
          result.contractAddress,
          computeCreateAddress(key.address, BigInt.zero),
        );
        expect(result.transactionHash, startsWith('0x'));
      } finally {
        client.close();
        await node.close();
      }
    },
  );

  test(
    'deploy throws DeploymentException when the receipt status is failure',
    () async {
      final node = await _FakeEthNode.start(revertTransactions: true);
      final key = EthPrivateKey.createRandom();
      final client = EthereumClient(node.uri);
      final deployer = ContractDeployer(client);

      try {
        await expectLater(
          deployer.deploy(
            credentials: key,
            bytecode: Uint8List.fromList([0x60, 0x80]),
            pollInterval: const Duration(milliseconds: 10),
            timeout: const Duration(seconds: 5),
          ),
          throwsA(isA<DeploymentException>()),
        );
      } finally {
        client.close();
        await node.close();
      }
    },
  );
}
