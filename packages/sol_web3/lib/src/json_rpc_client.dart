/// A minimal JSON-RPC 2.0 client over HTTP, using `dart:io` directly so the
/// package needs no third-party HTTP dependency.
library;

import 'dart:convert';
import 'dart:io';

/// Thrown when a JSON-RPC call returns an `error` member, or when the
/// transport / response framing is malformed.
class JsonRpcException implements Exception {
  JsonRpcException(this.message, {this.code});

  final String message;
  final int? code;

  @override
  String toString() => code == null
      ? 'JsonRpcException: $message'
      : 'JsonRpcException($code): $message';
}

/// Sends JSON-RPC 2.0 requests to a single HTTP endpoint (e.g. an Ethereum
/// node's RPC URL) and returns the decoded `result` of each call.
class JsonRpcClient {
  JsonRpcClient(this.endpoint, {HttpClient? httpClient})
    : _httpClient = httpClient ?? HttpClient();

  final Uri endpoint;
  final HttpClient _httpClient;
  int _nextId = 1;

  /// Calls [method] with positional [params] and returns the decoded
  /// `result`. Throws [JsonRpcException] on a JSON-RPC error response or a
  /// non-2xx HTTP status.
  Future<Object?> call(String method, [List<Object?> params = const []]) async {
    final id = _nextId++;
    final body = jsonEncode({
      'jsonrpc': '2.0',
      'id': id,
      'method': method,
      'params': params,
    });

    final request = await _httpClient.postUrl(endpoint);
    request.headers.contentType = ContentType.json;
    request.write(body);
    final response = await request.close();
    final responseBody = await response.transform(utf8.decoder).join();

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw JsonRpcException(
        'HTTP ${response.statusCode} from $endpoint: $responseBody',
      );
    }

    final decoded = jsonDecode(responseBody);
    if (decoded is! Map<String, dynamic>) {
      throw JsonRpcException('malformed JSON-RPC response: $responseBody');
    }
    final error = decoded['error'];
    if (error is Map<String, dynamic>) {
      throw JsonRpcException(
        error['message']?.toString() ?? 'unknown JSON-RPC error',
        code: error['code'] is int ? error['code'] as int : null,
      );
    }
    return decoded['result'];
  }

  /// Closes the underlying HTTP client. Call when finished issuing requests.
  void close() => _httpClient.close(force: true);
}
