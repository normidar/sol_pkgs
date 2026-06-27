/// Common interface for JSON-RPC transports (HTTP request/response,
/// WebSocket bidirectional). Lets `EthereumClient` work over either one.
library;

import 'dart:async';

abstract class JsonRpcTransport {
  /// Sends a JSON-RPC 2.0 request and resolves with the decoded `result`.
  Future<Object?> call(String method, [List<Object?> params = const []]);

  /// Releases the underlying network resources.
  FutureOr<void> close();
}
