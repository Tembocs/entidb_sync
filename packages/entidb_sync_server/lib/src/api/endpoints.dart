/// Sync API Endpoints
///
/// HTTP endpoint handlers for the sync protocol.
library;

import 'dart:typed_data';

import 'package:entidb_sync_protocol/entidb_sync_protocol.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

import '../sync/sync_service.dart';

/// Creates the sync API router.
Router createSyncRouter(SyncService syncService) {
  final router = Router();

  // Health check
  router.get('/health', (Request request) {
    return Response.ok('{"status": "ok"}', headers: _jsonHeaders);
  });

  // Protocol version info
  router.get('/v1/version', (Request request) {
    return Response.ok(
      '{"version": ${ProtocolVersion.v1.current}, "minSupported": ${ProtocolVersion.v1.minSupported}}',
      headers: _jsonHeaders,
    );
  });

  // Handshake endpoint
  router.post('/v1/handshake', (Request request) async {
    try {
      final body = await request.read().expand((x) => x).toList();
      final bytes = Uint8List.fromList(body);

      final handshakeRequest = HandshakeRequest.fromBytes(bytes);
      final response = await syncService.handleHandshake(handshakeRequest);

      return Response.ok(
        response.toBytes(),
        headers: _cborHeaders,
      );
    } catch (e) {
      return _errorResponse(400, 'Invalid handshake request: $e');
    }
  });

  // Pull endpoint
  router.post('/v1/pull', (Request request) async {
    try {
      final body = await request.read().expand((x) => x).toList();
      final bytes = Uint8List.fromList(body);

      final pullRequest = PullRequest.fromBytes(bytes);
      final response = await syncService.handlePull(pullRequest);

      return Response.ok(
        response.toBytes(),
        headers: _cborHeaders,
      );
    } catch (e) {
      return _errorResponse(400, 'Invalid pull request: $e');
    }
  });

  // Push endpoint
  router.post('/v1/push', (Request request) async {
    try {
      final body = await request.read().expand((x) => x).toList();
      final bytes = Uint8List.fromList(body);

      final pushRequest = PushRequest.fromBytes(bytes);
      final response = await syncService.handlePush(pushRequest);

      return Response.ok(
        response.toBytes(),
        headers: _cborHeaders,
      );
    } catch (e) {
      return _errorResponse(400, 'Invalid push request: $e');
    }
  });

  // Server stats (for debugging)
  router.get('/v1/stats', (Request request) {
    return Response.ok(
      '{"cursor": ${syncService.currentCursor}, "oplogSize": ${syncService.oplogSize}}',
      headers: _jsonHeaders,
    );
  });

  return router;
}

const _jsonHeaders = {
  'Content-Type': 'application/json',
};

const _cborHeaders = {
  'Content-Type': 'application/cbor',
};

Response _errorResponse(int statusCode, String message) {
  return Response(
    statusCode,
    body: '{"error": "$message"}',
    headers: _jsonHeaders,
  );
}
