import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:sol_web3/sol_web3.dart';
import 'package:test/test.dart';

void main() {
  group('WebSocketJsonRpcClient', () {
    late HttpServer server;
    late Uri wsUri;

    setUp(() async {
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      wsUri = Uri.parse('ws://127.0.0.1:${server.port}/');
      // Server-side loop: accept the upgrade and act as a tiny mock node.
      unawaited(_serve(server));
    });

    tearDown(() async {
      await server.close(force: true);
    });

    test('request/response round-trip resolves the awaited future', () async {
      final client = await WebSocketJsonRpcClient.connect(wsUri);
      try {
        final chainId = await client.call('eth_chainId');
        expect(chainId, '0x1');
      } finally {
        await client.close();
      }
    });

    test(
      'eth_subscribe delivers notifications via the returned stream',
      () async {
        final client = await WebSocketJsonRpcClient.connect(wsUri);
        try {
          final sub = await client.subscribe('newHeads');
          expect(sub.id, '0xsub1');

          // Ask the mock to push one notification on the active subscription.
          await client.call('mock_emit', [sub.id, 'hello']);

          final first = await sub.events.first.timeout(
            const Duration(seconds: 2),
          );
          expect(first['subscription'], sub.id);
          expect(first['result'], 'hello');

          final ok = await client.unsubscribe(sub.id);
          expect(ok, isTrue);
        } finally {
          await client.close();
        }
      },
    );

    test('error responses surface as JsonRpcException', () async {
      final client = await WebSocketJsonRpcClient.connect(wsUri);
      try {
        await expectLater(
          client.call('mock_error'),
          throwsA(isA<JsonRpcException>()),
        );
      } finally {
        await client.close();
      }
    });
  });
}

/// Minimal mock node: responds to `eth_chainId`, `eth_subscribe`,
/// `eth_unsubscribe`, `mock_emit` (pushes a notification), and `mock_error`
/// (returns an error response).
Future<void> _serve(HttpServer server) async {
  await for (final req in server) {
    if (!WebSocketTransformer.isUpgradeRequest(req)) {
      req.response.statusCode = 400;
      await req.response.close();
      continue;
    }
    final ws = await WebSocketTransformer.upgrade(req);
    ws.listen((dynamic raw) async {
      final msg = jsonDecode(raw as String) as Map<String, dynamic>;
      final id = msg['id'];
      final method = msg['method'] as String;
      final params = (msg['params'] as List?) ?? const [];

      String reply(Object? result) =>
          jsonEncode({'jsonrpc': '2.0', 'id': id, 'result': result});

      switch (method) {
        case 'eth_chainId':
          ws.add(reply('0x1'));
        case 'eth_subscribe':
          ws.add(reply('0xsub1'));
        case 'eth_unsubscribe':
          ws.add(reply(true));
        case 'mock_emit':
          ws.add(reply(true));
          ws.add(
            jsonEncode({
              'jsonrpc': '2.0',
              'method': 'eth_subscription',
              'params': {'subscription': params[0], 'result': params[1]},
            }),
          );
        case 'mock_error':
          ws.add(
            jsonEncode({
              'jsonrpc': '2.0',
              'id': id,
              'error': {'code': -32601, 'message': 'method not found'},
            }),
          );
        default:
          ws.add(reply(null));
      }
    });
  }
}
