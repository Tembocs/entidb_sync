/// Sync Service
///
/// Core synchronization logic for the server.
library;

import 'dart:typed_data';

import 'package:entidb_sync_protocol/entidb_sync_protocol.dart';
import 'package:synchronized/synchronized.dart';

import '../sse/sse_manager.dart';

/// Callback for SSE broadcast when operations are pushed.
typedef OperationBroadcastCallback =
    void Function(List<SyncOperation> operations, int cursor);

/// In-memory sync service for demonstration purposes.
///
/// In production, this would use EntiDB for persistence.
class SyncService {
  /// Server's operation log (in-memory for now).
  final List<SyncOperation> _oplog = [];

  /// Per-device cursors tracking sync progress.
  final Map<String, int> _deviceCursors = {};

  /// Global operation counter.
  int _globalOpId = 0;

  /// Lock for thread-safe operations.
  final Lock _lock = Lock();

  /// Optional SSE manager for real-time updates.
  SseManager? _sseManager;

  /// Callback for broadcasting operations.
  OperationBroadcastCallback? _broadcastCallback;

  /// Sets the SSE manager for real-time broadcasts.
  void setSseManager(SseManager manager) {
    _sseManager = manager;
    _broadcastCallback = manager.broadcast;
  }

  /// Sets a custom broadcast callback.
  void setBroadcastCallback(OperationBroadcastCallback callback) {
    _broadcastCallback = callback;
  }

  /// Processes a handshake request.
  Future<HandshakeResponse> handleHandshake(HandshakeRequest request) async {
    return await _lock.synchronized(() async {
      // Register or update device cursor
      _deviceCursors.putIfAbsent(request.deviceId, () => 0);

      return HandshakeResponse(
        serverCursor: _globalOpId,
        capabilities: ServerCapabilities(sse: _sseManager != null),
      );
    });
  }

  /// Processes a pull request.
  Future<PullResponse> handlePull(PullRequest request) async {
    return await _lock.synchronized(() async {
      // Get operations since cursor
      final ops = _oplog
          .where((op) => op.opId > request.sinceCursor)
          .take(request.limit)
          .toList();

      // Apply collection filter if provided
      final filteredOps = request.collections != null
          ? ops
                .where((op) => request.collections!.contains(op.collection))
                .toList()
          : ops;

      // Calculate next cursor
      final nextCursor = filteredOps.isEmpty
          ? request.sinceCursor
          : filteredOps.last.opId;

      // Check if more operations available
      final hasMore = _oplog.any((op) => op.opId > nextCursor);

      return PullResponse(
        ops: filteredOps,
        nextCursor: nextCursor,
        hasMore: hasMore,
      );
    });
  }

  /// Processes a push request.
  Future<PushResponse> handlePush(PushRequest request) async {
    return await _lock.synchronized(() async {
      final conflicts = <Conflict>[];
      final acceptedOps = <SyncOperation>[];
      int acknowledgedUpToOpId = 0;

      for (final clientOp in request.ops) {
        // Check for conflicts
        final conflict = _detectConflict(clientOp);

        if (conflict != null) {
          conflicts.add(conflict);
          continue;
        }

        // Accept the operation
        _globalOpId++;
        final serverOp = SyncOperation(
          opId: _globalOpId,
          dbId: clientOp.dbId,
          deviceId: clientOp.deviceId,
          collection: clientOp.collection,
          entityId: clientOp.entityId,
          opType: clientOp.opType,
          entityVersion: clientOp.entityVersion,
          entityCbor: clientOp.entityCbor,
          timestampMs: DateTime.now().millisecondsSinceEpoch,
        );

        _oplog.add(serverOp);
        acceptedOps.add(serverOp);
        acknowledgedUpToOpId = clientOp.opId;
      }

      // Update device cursor
      if (acknowledgedUpToOpId > 0) {
        _deviceCursors[request.deviceId] = _globalOpId;
      }

      // Broadcast accepted operations via SSE
      if (acceptedOps.isNotEmpty && _broadcastCallback != null) {
        _broadcastCallback!(acceptedOps, _globalOpId);
      }

      return PushResponse(
        acknowledgedUpToOpId: acknowledgedUpToOpId,
        conflicts: conflicts,
      );
    });
  }

  /// Detects conflicts for an incoming operation.
  Conflict? _detectConflict(SyncOperation clientOp) {
    // Find the latest server operation for this entity
    final serverOps = _oplog
        .where(
          (op) =>
              op.collection == clientOp.collection &&
              op.entityId == clientOp.entityId,
        )
        .toList();

    if (serverOps.isEmpty) {
      // No existing entity, no conflict
      return null;
    }

    final latestServerOp = serverOps.last;

    // Conflict if client version is older than server version
    if (clientOp.entityVersion <= latestServerOp.entityVersion) {
      return Conflict(
        collection: clientOp.collection,
        entityId: clientOp.entityId,
        clientOp: clientOp,
        serverState: ServerState(
          entityVersion: latestServerOp.entityVersion,
          entityCbor: latestServerOp.entityCbor ?? Uint8List(0),
          lastModified: DateTime.fromMillisecondsSinceEpoch(
            latestServerOp.timestampMs,
          ),
        ),
      );
    }

    return null;
  }

  /// Gets the current server cursor.
  int get currentCursor => _globalOpId;

  /// Gets the total number of operations in the log.
  int get oplogSize => _oplog.length;
}
