/// HTTP Transport
///
/// HTTP client for communicating with the sync server.
library;

import 'dart:typed_data';

import 'package:entidb_sync_protocol/entidb_sync_protocol.dart';
import 'package:http/http.dart' as http;
import 'package:logging/logging.dart';
import 'package:retry/retry.dart';

/// Configuration for HTTP transport.
class TransportConfig {
  /// Base URL of the sync server.
  final Uri serverUrl;

  /// Database identifier.
  final String dbId;

  /// Device identifier.
  final String deviceId;

  /// Function to provide auth token.
  final Future<String?> Function()? authTokenProvider;

  /// Request timeout duration.
  final Duration timeout;

  /// Maximum retry attempts.
  final int maxRetries;

  const TransportConfig({
    required this.serverUrl,
    required this.dbId,
    required this.deviceId,
    this.authTokenProvider,
    this.timeout = const Duration(seconds: 30),
    this.maxRetries = 3,
  });
}

/// HTTP transport for sync protocol.
class SyncHttpTransport {
  final TransportConfig _config;
  final http.Client _client;
  final Logger _log = Logger('SyncHttpTransport');

  SyncHttpTransport({
    required TransportConfig config,
    http.Client? client,
  })  : _config = config,
        _client = client ?? http.Client();

  /// Performs handshake with the server.
  Future<HandshakeResponse> handshake(ClientInfo clientInfo) async {
    final request = HandshakeRequest(
      dbId: _config.dbId,
      deviceId: _config.deviceId,
      clientInfo: clientInfo,
    );

    final response = await _post('/v1/handshake', request.toBytes());
    return HandshakeResponse.fromBytes(response);
  }

  /// Pulls operations from the server.
  Future<PullResponse> pull({
    required int sinceCursor,
    int limit = 100,
    List<String>? collections,
  }) async {
    final request = PullRequest(
      dbId: _config.dbId,
      sinceCursor: sinceCursor,
      limit: limit,
      collections: collections,
    );

    final response = await _post('/v1/pull', request.toBytes());
    return PullResponse.fromBytes(response);
  }

  /// Pushes operations to the server.
  Future<PushResponse> push(List<SyncOperation> ops) async {
    final request = PushRequest(
      dbId: _config.dbId,
      deviceId: _config.deviceId,
      ops: ops,
    );

    final response = await _post('/v1/push', request.toBytes());
    return PushResponse.fromBytes(response);
  }

  /// Makes a POST request with retry logic.
  Future<Uint8List> _post(String path, Uint8List body) async {
    final url = _config.serverUrl.resolve(path);
    final headers = await _buildHeaders();

    _log.fine('POST $url (${body.length} bytes)');

    final r = RetryOptions(
      maxAttempts: _config.maxRetries,
      delayFactor: const Duration(milliseconds: 500),
    );

    try {
      final response = await r.retry(
        () async {
          final resp = await _client
              .post(url, headers: headers, body: body)
              .timeout(_config.timeout);

          if (resp.statusCode >= 500) {
            throw http.ClientException('Server error: ${resp.statusCode}');
          }

          return resp;
        },
        retryIf: (e) => e is http.ClientException,
      );

      if (response.statusCode != 200) {
        throw SyncTransportException(
          'Request failed with status ${response.statusCode}',
          statusCode: response.statusCode,
          body: response.body,
        );
      }

      _log.fine(
          'Response: ${response.statusCode} (${response.bodyBytes.length} bytes)');
      return Uint8List.fromList(response.bodyBytes);
    } catch (e) {
      _log.warning('Request failed: $e');
      rethrow;
    }
  }

  /// Builds request headers.
  Future<Map<String, String>> _buildHeaders() async {
    final headers = <String, String>{
      'Content-Type': 'application/cbor',
      'Accept': 'application/cbor',
    };

    if (_config.authTokenProvider != null) {
      final token = await _config.authTokenProvider!();
      if (token != null) {
        headers['Authorization'] = 'Bearer $token';
      }
    }

    return headers;
  }

  /// Closes the HTTP client.
  void close() {
    _client.close();
  }
}

/// Exception thrown when transport fails.
class SyncTransportException implements Exception {
  final String message;
  final int? statusCode;
  final String? body;

  SyncTransportException(
    this.message, {
    this.statusCode,
    this.body,
  });

  @override
  String toString() => 'SyncTransportException: $message'
      '${statusCode != null ? ' (status: $statusCode)' : ''}'
      '${body != null ? '\nBody: $body' : ''}';
}
