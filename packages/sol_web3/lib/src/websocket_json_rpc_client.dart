/// JSON-RPC 2.0 client over a WebSocket connection, with `eth_subscribe`
/// support. Uses `dart:io`'s built-in [WebSocket] so the package keeps its
/// no-third-party-dependency stance.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'json_rpc_client.dart' show JsonRpcException;
import 'json_rpc_transport.dart';

/// A push-capable JSON-RPC transport. Each call gets a unique numeric id;
/// responses are dispatched back to the awaiting future by id. Subscription
/// notifications (`method: "eth_subscription"`) are routed to per-subscription
/// streams.
class WebSocketJsonRpcClient implements JsonRpcTransport {
  WebSocketJsonRpcClient._(this._socket) {
    _listen();
  }

  /// Connects to [endpoint] (`ws://` or `wss://`) and returns a ready client.
  static Future<WebSocketJsonRpcClient> connect(Uri endpoint) async {
    final socket = await WebSocket.connect(endpoint.toString());
    return WebSocketJsonRpcClient._(socket);
  }

  /// Wraps an already-connected [WebSocket]. Useful in tests that supply a
  /// loopback server.
  WebSocketJsonRpcClient.fromSocket(WebSocket socket) : _socket = socket {
    _listen();
  }

  final WebSocket _socket;
  final Map<int, Completer<Object?>> _pending = {};
  final Map<String, StreamController<Map<String, dynamic>>> _subs = {};
  int _nextId = 1;
  bool _closed = false;

  void _listen() {
    _socket.listen(
      _onMessage,
      onError: (Object e, StackTrace st) {
        _completeAllErrors(e, st);
      },
      onDone: () {
        _closed = true;
        _completeAllErrors(
          JsonRpcException('WebSocket closed before response'),
          StackTrace.current,
        );
        for (final c in _subs.values) {
          c.close();
        }
      },
      cancelOnError: false,
    );
  }

  void _onMessage(dynamic data) {
    final text = data is String ? data : utf8.decode(data as List<int>);
    final msg = jsonDecode(text);
    if (msg is! Map<String, dynamic>) return;

    // Subscription notification: { jsonrpc, method: eth_subscription, params: { subscription, result } }
    if (msg['method'] == 'eth_subscription' && msg['params'] is Map) {
      final params = msg['params'] as Map<String, dynamic>;
      final subId = params['subscription'] as String?;
      if (subId == null) return;
      final controller = _subs[subId];
      if (controller != null && !controller.isClosed) {
        controller.add(params);
      }
      return;
    }

    // Response to a previous request: must carry an `id`.
    final id = msg['id'];
    if (id is! int) return;
    final completer = _pending.remove(id);
    if (completer == null) return;

    final error = msg['error'];
    if (error is Map<String, dynamic>) {
      completer.completeError(
        JsonRpcException(
          error['message']?.toString() ?? 'unknown JSON-RPC error',
          code: error['code'] is int ? error['code'] as int : null,
        ),
      );
    } else {
      completer.complete(msg['result']);
    }
  }

  void _completeAllErrors(Object error, StackTrace st) {
    final pending = List.of(_pending.values);
    _pending.clear();
    for (final c in pending) {
      if (!c.isCompleted) c.completeError(error, st);
    }
  }

  @override
  Future<Object?> call(String method, [List<Object?> params = const []]) {
    if (_closed) {
      return Future.error(JsonRpcException('WebSocket is closed'));
    }
    final id = _nextId++;
    final completer = Completer<Object?>();
    _pending[id] = completer;
    _socket.add(
      jsonEncode({
        'jsonrpc': '2.0',
        'id': id,
        'method': method,
        'params': params,
      }),
    );
    return completer.future;
  }

  /// Subscribes to [kind] (`"newHeads"`, `"logs"`,
  /// `"newPendingTransactions"`) and returns the subscription id and a stream
  /// of the raw notification payloads. Each payload's `"result"` field
  /// carries the event-specific body (block header, log entry, tx hash).
  Future<({String id, Stream<Map<String, dynamic>> events})> subscribe(
    String kind, [
    Map<String, Object?>? options,
  ]) async {
    final params = options == null ? [kind] : [kind, options];
    final result = await call('eth_subscribe', params);
    if (result is! String) {
      throw JsonRpcException('eth_subscribe did not return a subscription id');
    }
    // Single-subscriber so late listeners still see buffered events; the
    // typical consumer is `await for (final h in events) { ... }`.
    final controller = StreamController<Map<String, dynamic>>();
    _subs[result] = controller;
    return (id: result, events: controller.stream);
  }

  /// Cancels a subscription previously created by [subscribe]. Returns the
  /// node's boolean acknowledgement.
  Future<bool> unsubscribe(String subscriptionId) async {
    final ok = await call('eth_unsubscribe', [subscriptionId]);
    await _subs.remove(subscriptionId)?.close();
    return ok is bool ? ok : false;
  }

  @override
  Future<void> close() async {
    _closed = true;
    for (final c in _subs.values) {
      await c.close();
    }
    _subs.clear();
    await _socket.close();
  }
}
