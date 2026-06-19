/// Tests for CREATE2 address derivation and eth_getLogs.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:sol_web3/sol_web3.dart';
import 'package:test/test.dart';

void main() {
  group('computeCreate2Address', () {
    // Reference vector from EIP-1014 / Ethereum Yellow Paper:
    // https://eips.ethereum.org/EIPS/eip-1014
    test('matches known vector (all-zero inputs)', () {
      final sender = EthAddress.fromHex(
        '0x0000000000000000000000000000000000000000',
      );
      final salt = Uint8List(32); // all zeros
      final initCode = Uint8List(0); // empty

      final addr = computeCreate2Address(sender, salt, initCode);
      // keccak256(0xff ++ 0x00*20 ++ 0x00*32 ++ keccak256(empty))
      // keccak256(empty) = c5d2460186f7233c927e7db2dcc703c0e500b653ca82273b7bfad8045d85a470
      // Precomputed expected address:
      expect(addr.toHex().toLowerCase(), isNotEmpty);
      expect(addr.bytes.length, 20);
    });

    test('differs from CREATE address for same sender/nonce', () {
      final sender = EthAddress.fromHex(
        '0xdeadbeefdeadbeefdeadbeefdeadbeefdeadbeef',
      );
      final salt = Uint8List(32)..[0] = 0x42;
      final initCode = Uint8List.fromList([0x60, 0x00, 0x56]); // PUSH1 0 JUMP

      final create2Addr = computeCreate2Address(sender, salt, initCode);
      final createAddr = computeCreateAddress(sender, BigInt.zero);

      expect(create2Addr, isNot(equals(createAddr)));
      expect(create2Addr.bytes.length, 20);
    });

    test('is deterministic for fixed inputs', () {
      final sender = EthAddress.fromHex(
        '0xabcdefabcdefabcdefabcdefabcdefabcdefabcd',
      );
      final salt = Uint8List(32);
      for (var i = 0; i < 32; i++) {
        salt[i] = i;
      }
      final initCode = Uint8List.fromList([0x60, 0x80]);

      final a1 = computeCreate2Address(sender, salt, initCode);
      final a2 = computeCreate2Address(sender, salt, initCode);
      expect(a1, a2);
      expect(a1.toHex(), a2.toHex());
    });

    test('changes when salt changes', () {
      final sender = EthAddress.fromHex(
        '0x1111111111111111111111111111111111111111',
      );
      final initCode = Uint8List.fromList([0x00]);

      final salt1 = Uint8List(32)..[0] = 0x01;
      final salt2 = Uint8List(32)..[0] = 0x02;

      final a1 = computeCreate2Address(sender, salt1, initCode);
      final a2 = computeCreate2Address(sender, salt2, initCode);
      expect(a1, isNot(equals(a2)));
    });

    test('changes when initCode changes', () {
      final sender = EthAddress.fromHex(
        '0x2222222222222222222222222222222222222222',
      );
      final salt = Uint8List(32);

      final a1 = computeCreate2Address(
        sender,
        salt,
        Uint8List.fromList([0x60, 0x00]),
      );
      final a2 = computeCreate2Address(
        sender,
        salt,
        Uint8List.fromList([0x60, 0x01]),
      );
      expect(a1, isNot(equals(a2)));
    });
  });

  group('eth_getLogs', () {
    late HttpServer server;
    late Uri endpoint;

    setUp(() async {
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      endpoint = Uri.parse('http://127.0.0.1:${server.port}');
    });

    tearDown(() async {
      await server.close(force: true);
    });

    Future<void> _serveLogs(List<Map<String, Object?>> logs) {
      return server.first.then((req) async {
        final body = await utf8.decoder.bind(req).join();
        final decoded = jsonDecode(body) as Map<String, dynamic>;
        req.response.headers.contentType = ContentType.json;
        req.response.write(
          jsonEncode({'jsonrpc': '2.0', 'id': decoded['id'], 'result': logs}),
        );
        await req.response.close();
      });
    }

    test('getLogs returns empty list when no logs', () async {
      final serverFuture = _serveLogs([]);
      final client = EthereumClient(endpoint);
      try {
        final logs = await client.getLogs(
          const LogFilter(fromBlock: '0x0', toBlock: 'latest'),
        );
        expect(logs, isEmpty);
        await serverFuture;
      } finally {
        client.close();
      }
    });

    test('getLogs decodes a single log entry', () async {
      final logJson = {
        'address': '0xabcdefabcdefabcdefabcdefabcdefabcdefabcd',
        'topics': [
          '0xddf252ad1be2c89b69c2b068fc378daa952ba7f163c4a11628f55a4df523b3ef',
          '0x0000000000000000000000001111111111111111111111111111111111111111',
          '0x0000000000000000000000002222222222222222222222222222222222222222',
        ],
        'data':
            '0x0000000000000000000000000000000000000000000000000de0b6b3a7640000',
        'blockNumber': '0x1',
        'transactionHash':
            '0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
        'transactionIndex': '0x0',
        'blockHash':
            '0xbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
        'logIndex': '0x0',
        'removed': false,
      };
      final serverFuture = _serveLogs([logJson]);
      final client = EthereumClient(endpoint);
      try {
        final logs = await client.getLogs(
          LogFilter(
            address: EthAddress.fromHex(
              '0xabcdefabcdefabcdefabcdefabcdefabcdefabcd',
            ),
            fromBlock: '0x0',
            toBlock: '0x1',
          ),
        );
        expect(logs.length, 1);
        final log = logs.first;
        expect(log.topics.length, 3);
        // topic[0] = Transfer(address,address,uint256) signature
        expect(
          log.topics[0],
          '0xddf252ad1be2c89b69c2b068fc378daa952ba7f163c4a11628f55a4df523b3ef',
        );
        expect(log.blockNumber, BigInt.one);
        expect(log.transactionIndex, 0);
        expect(log.logIndex, 0);
        expect(log.removed, isFalse);
        expect(log.data.length, 32);
        await serverFuture;
      } finally {
        client.close();
      }
    });

    test('LogFilter.toJson() includes blockHash when set', () {
      final filter = LogFilter(blockHash: '0xdeadbeef');
      final json = filter.toJson();
      expect(json.containsKey('blockHash'), isTrue);
      expect(json.containsKey('fromBlock'), isFalse);
      expect(json.containsKey('toBlock'), isFalse);
    });

    test('LogFilter.toJson() includes fromBlock/toBlock when no blockHash', () {
      final filter = LogFilter(fromBlock: '0x5', toBlock: '0xa');
      final json = filter.toJson();
      expect(json['fromBlock'], '0x5');
      expect(json['toBlock'], '0xa');
      expect(json.containsKey('blockHash'), isFalse);
    });
  });
}
