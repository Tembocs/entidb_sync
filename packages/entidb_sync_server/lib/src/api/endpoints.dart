/// Sync API Endpoints
///
/// HTTP endpoint handlers for the sync protocol.
library;

import 'dart:async';
import 'dart:typed_data';

import 'package:entidb_sync_protocol/entidb_sync_protocol.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

import '../sse/sse_manager.dart';
import '../sync/sync_service.dart';

/// Creates the sync API router.
///
/// If [sseManager] is provided, enables real-time SSE updates.
Router createSyncRouter(SyncService syncService, {SseManager? sseManager}) {
  final router = Router();

  // Wire up SSE if provided
  if (sseManager != null) {
    syncService.setSseManager(sseManager);
  }

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

      return Response.ok(response.toBytes(), headers: _cborHeaders);
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

      return Response.ok(response.toBytes(), headers: _cborHeaders);
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

      return Response.ok(response.toBytes(), headers: _cborHeaders);
    } catch (e) {
      return _errorResponse(400, 'Invalid push request: $e');
    }
  });

  // Server stats (for debugging)
  router.get('/v1/stats', (Request request) {
    final sseStats = sseManager?.stats ?? {};
    return Response.ok(
      '{"cursor": ${syncService.currentCursor}, "oplogSize": ${syncService.oplogSize}, "sse": $sseStats}',
      headers: _jsonHeaders,
    );
  });

  // SSE endpoint for real-time updates
  if (sseManager != null) {
    router.get('/v1/events', (Request request) {
      return _handleSseRequest(request, syncService, sseManager);
    });
  }

  return router;
}

const _jsonHeaders = {'Content-Type': 'application/json'};

const _cborHeaders = {'Content-Type': 'application/cbor'};

const _sseHeaders = {
  'Content-Type': 'text/event-stream',
  'Cache-Control': 'no-cache',
  'Connection': 'keep-alive',
  'X-Accel-Buffering': 'no', // Disable nginx buffering
};

Response _errorResponse(int statusCode, String message) {
  return Response(
    statusCode,
    body: '{"error": "$message"}',
    headers: _jsonHeaders,
  );
}

/// Handles SSE subscription request.
Response _handleSseRequest(
  Request request,
  SyncService syncService,
  SseManager sseManager,
) {
  // Get device ID from auth context or query param
  final deviceId = request.url.queryParameters['deviceId'];
  if (deviceId == null || deviceId.isEmpty) {
    return _errorResponse(400, 'Missing deviceId query parameter');
  }

  // Get optional collection filter
  final collectionsParam = request.url.queryParameters['collections'];
  final collections = collectionsParam
      ?.split(',')
      .where((c) => c.isNotEmpty)
      .toList();

  // Create subscription
  final subscription = sseManager.subscribe(
    deviceId: deviceId,
    collections: collections,
  );

  if (subscription == null) {
    return _errorResponse(429, 'Too many SSE connections');
  }

  // Send connected event with current cursor
  sseManager.sendConnectedEvent(subscription, syncService.currentCursor);

  // Create streaming response
  final streamController = StreamController<List<int>>();

  // Forward SSE events to the stream
  final sseListener = subscription.stream.listen(
    (event) {
      streamController.add(event.codeUnits);
    },
    onError: (Object error) {
      streamController.addError(error);
    },
    onDone: () {
      streamController.close();
    },
  );

  // Clean up when client disconnects
  streamController.onCancel = () {
    sseListener.cancel();
    sseManager.unsubscribe(subscription.subscriptionId);
  };

  return Response.ok(streamController.stream, headers: _sseHeaders);
}
