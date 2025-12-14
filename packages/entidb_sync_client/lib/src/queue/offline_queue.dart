/// Offline Queue
///
/// Persistent queue for operations pending synchronization.
///
/// The OfflineQueue stores operations locally when the client is offline
/// and provides them to the SyncEngine for pushing when connectivity
/// is restored.
///
/// ## Features
///
/// - **Persistent storage:** Operations survive app restarts
/// - **Ordering guarantees:** FIFO ordering preserved
/// - **Deduplication:** Prevents duplicate operations
/// - **Acknowledgment:** Removes synced operations
/// - **Retry tracking:** Tracks failed push attempts
///
/// ## Usage
///
/// ```dart
/// final queue = OfflineQueue(storagePath: './sync_queue');
/// await queue.open();
///
/// // Enqueue operations from oplog
/// await queue.enqueue(operation);
///
/// // Get pending operations for push
/// final pending = await queue.getPending(limit: 100);
///
/// // Acknowledge synced operations
/// await queue.acknowledge(upToOpId: 42);
/// ```
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:entidb_sync_protocol/entidb_sync_protocol.dart';

/// Persistent offline queue for sync operations.
///
/// Stores operations locally and provides them for synchronization
/// when connectivity is available.
class OfflineQueue {
  final String _storagePath;
  final int _maxRetries;

  /// In-memory queue (backed by persistent storage).
  final List<QueuedOperation> _queue = [];

  /// Index for fast lookup by opId.
  final Map<int, int> _opIdIndex = {};

  bool _isOpen = false;

  /// Creates an offline queue with the specified storage path.
  ///
  /// - [storagePath]: Directory path for queue persistence.
  /// - [maxRetries]: Maximum retry attempts before marking as failed.
  OfflineQueue({required String storagePath, int maxRetries = 5})
    : _storagePath = storagePath,
      _maxRetries = maxRetries;

  /// Whether the queue is currently open.
  bool get isOpen => _isOpen;

  /// Number of pending operations.
  int get length => _queue.length;

  /// Whether the queue is empty.
  bool get isEmpty => _queue.isEmpty;

  /// Whether the queue has pending operations.
  bool get isNotEmpty => _queue.isNotEmpty;

  /// Opens the queue and loads persisted operations.
  ///
  /// Creates the storage directory if it doesn't exist.
  /// Loads any previously persisted operations.
  ///
  /// Throws [StateError] if already open.
  Future<void> open() async {
    if (_isOpen) {
      throw StateError('OfflineQueue is already open');
    }

    final dir = Directory(_storagePath);
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }

    await _loadFromDisk();
    _isOpen = true;
  }

  /// Closes the queue and persists pending operations.
  ///
  /// After closing, the queue cannot be used until reopened.
  Future<void> close() async {
    if (!_isOpen) return;

    await _saveToDisk();
    _queue.clear();
    _opIdIndex.clear();
    _isOpen = false;
  }

  /// Enqueues an operation for synchronization.
  ///
  /// The operation is persisted immediately.
  /// Duplicate operations (same opId) are ignored.
  ///
  /// Returns `true` if the operation was added, `false` if duplicate.
  ///
  /// Throws [StateError] if the queue is not open.
  Future<bool> enqueue(SyncOperation operation) async {
    _checkOpen();

    // Check for duplicate
    if (_opIdIndex.containsKey(operation.opId)) {
      return false;
    }

    final queued = QueuedOperation(
      operation: operation,
      enqueuedAt: DateTime.now(),
      retryCount: 0,
      status: QueueStatus.pending,
    );

    _queue.add(queued);
    _opIdIndex[operation.opId] = _queue.length - 1;

    await _saveToDisk();
    return true;
  }

  /// Enqueues multiple operations atomically.
  ///
  /// Returns the number of operations actually added (excludes duplicates).
  Future<int> enqueueAll(List<SyncOperation> operations) async {
    _checkOpen();

    int added = 0;
    for (final op in operations) {
      if (!_opIdIndex.containsKey(op.opId)) {
        final queued = QueuedOperation(
          operation: op,
          enqueuedAt: DateTime.now(),
          retryCount: 0,
          status: QueueStatus.pending,
        );
        _queue.add(queued);
        _opIdIndex[op.opId] = _queue.length - 1;
        added++;
      }
    }

    if (added > 0) {
      await _saveToDisk();
    }

    return added;
  }

  /// Gets pending operations for synchronization.
  ///
  /// Returns operations in FIFO order, optionally filtered by status.
  /// Operations are not removed from the queue until acknowledged.
  ///
  /// - [sinceOpId]: Only return operations after this opId (exclusive).
  /// - [limit]: Maximum number of operations to return.
  /// - [includeRetrying]: Include operations that are being retried.
  Future<List<SyncOperation>> getPending({
    int sinceOpId = 0,
    int limit = 100,
    bool includeRetrying = true,
  }) async {
    _checkOpen();

    final results = <SyncOperation>[];

    for (final queued in _queue) {
      if (queued.operation.opId <= sinceOpId) continue;
      if (queued.status == QueueStatus.failed) continue;
      if (queued.status == QueueStatus.retrying && !includeRetrying) continue;

      results.add(queued.operation);
      if (results.length >= limit) break;
    }

    return results;
  }

  /// Acknowledges that operations up to the specified opId have been synced.
  ///
  /// Removes acknowledged operations from the queue.
  ///
  /// - [upToOpId]: Remove operations with opId <= this value.
  ///
  /// Returns the number of operations removed.
  Future<int> acknowledge(int upToOpId) async {
    _checkOpen();

    final toRemove = <int>[];

    for (var i = 0; i < _queue.length; i++) {
      if (_queue[i].operation.opId <= upToOpId) {
        toRemove.add(i);
      }
    }

    if (toRemove.isEmpty) return 0;

    // Remove in reverse order to preserve indices
    for (var i = toRemove.length - 1; i >= 0; i--) {
      final index = toRemove[i];
      _opIdIndex.remove(_queue[index].operation.opId);
      _queue.removeAt(index);
    }

    // Rebuild index
    _rebuildIndex();

    await _saveToDisk();
    return toRemove.length;
  }

  /// Marks an operation as failed after a push attempt.
  ///
  /// Increments retry count and updates status.
  /// Operations exceeding maxRetries are marked as permanently failed.
  ///
  /// - [opId]: The operation ID that failed.
  /// - [error]: Optional error message for logging.
  Future<void> markFailed(int opId, {String? error}) async {
    _checkOpen();

    final index = _opIdIndex[opId];
    if (index == null) return;

    final queued = _queue[index];
    final newRetryCount = queued.retryCount + 1;
    final newStatus = newRetryCount >= _maxRetries
        ? QueueStatus.failed
        : QueueStatus.retrying;

    _queue[index] = QueuedOperation(
      operation: queued.operation,
      enqueuedAt: queued.enqueuedAt,
      retryCount: newRetryCount,
      status: newStatus,
      lastError: error,
      lastAttemptAt: DateTime.now(),
    );

    await _saveToDisk();
  }

  /// Resets failed operations to pending status for retry.
  ///
  /// Useful after connectivity is restored or server issues are resolved.
  ///
  /// Returns the number of operations reset.
  Future<int> resetFailed() async {
    _checkOpen();

    int count = 0;
    for (var i = 0; i < _queue.length; i++) {
      if (_queue[i].status == QueueStatus.failed) {
        _queue[i] = QueuedOperation(
          operation: _queue[i].operation,
          enqueuedAt: _queue[i].enqueuedAt,
          retryCount: 0,
          status: QueueStatus.pending,
        );
        count++;
      }
    }

    if (count > 0) {
      await _saveToDisk();
    }

    return count;
  }

  /// Gets queue statistics.
  QueueStats getStats() {
    _checkOpen();

    int pending = 0;
    int retrying = 0;
    int failed = 0;

    for (final queued in _queue) {
      switch (queued.status) {
        case QueueStatus.pending:
          pending++;
        case QueueStatus.retrying:
          retrying++;
        case QueueStatus.failed:
          failed++;
      }
    }

    return QueueStats(
      total: _queue.length,
      pending: pending,
      retrying: retrying,
      failed: failed,
    );
  }

  /// Clears all operations from the queue.
  ///
  /// Use with caution - this discards any unsynced operations.
  Future<void> clear() async {
    _checkOpen();

    _queue.clear();
    _opIdIndex.clear();
    await _saveToDisk();
  }

  void _checkOpen() {
    if (!_isOpen) {
      throw StateError('OfflineQueue is not open. Call open() first.');
    }
  }

  void _rebuildIndex() {
    _opIdIndex.clear();
    for (var i = 0; i < _queue.length; i++) {
      _opIdIndex[_queue[i].operation.opId] = i;
    }
  }

  File get _queueFile => File('$_storagePath/queue.json');

  Future<void> _loadFromDisk() async {
    final file = _queueFile;
    if (!await file.exists()) return;

    try {
      final content = await file.readAsString();
      final json = jsonDecode(content) as Map<String, dynamic>;
      final items = json['items'] as List<dynamic>;

      for (final item in items) {
        final queued = QueuedOperation.fromJson(item as Map<String, dynamic>);
        _queue.add(queued);
        _opIdIndex[queued.operation.opId] = _queue.length - 1;
      }
    } catch (e) {
      // Log error but continue with empty queue
      // In production, use proper logging
    }
  }

  Future<void> _saveToDisk() async {
    final file = _queueFile;

    final json = {
      'version': 1,
      'savedAt': DateTime.now().toIso8601String(),
      'items': _queue.map((q) => q.toJson()).toList(),
    };

    await file.writeAsString(jsonEncode(json));
  }
}

/// Status of a queued operation.
enum QueueStatus {
  /// Waiting to be synced.
  pending,

  /// Failed but will be retried.
  retrying,

  /// Permanently failed (exceeded max retries).
  failed,
}

/// Wrapper for a queued sync operation with metadata.
class QueuedOperation {
  /// The sync operation to be pushed.
  final SyncOperation operation;

  /// When the operation was added to the queue.
  final DateTime enqueuedAt;

  /// Number of failed push attempts.
  final int retryCount;

  /// Current status.
  final QueueStatus status;

  /// Last error message (if failed).
  final String? lastError;

  /// Timestamp of last push attempt.
  final DateTime? lastAttemptAt;

  const QueuedOperation({
    required this.operation,
    required this.enqueuedAt,
    required this.retryCount,
    required this.status,
    this.lastError,
    this.lastAttemptAt,
  });

  /// Serializes to JSON for persistence.
  Map<String, dynamic> toJson() => {
    'operation': _syncOperationToJson(operation),
    'enqueuedAt': enqueuedAt.toIso8601String(),
    'retryCount': retryCount,
    'status': status.name,
    'lastError': lastError,
    'lastAttemptAt': lastAttemptAt?.toIso8601String(),
  };

  /// Deserializes from JSON.
  factory QueuedOperation.fromJson(Map<String, dynamic> json) {
    return QueuedOperation(
      operation: _syncOperationFromJson(
        json['operation'] as Map<String, dynamic>,
      ),
      enqueuedAt: DateTime.parse(json['enqueuedAt'] as String),
      retryCount: json['retryCount'] as int,
      status: QueueStatus.values.byName(json['status'] as String),
      lastError: json['lastError'] as String?,
      lastAttemptAt: json['lastAttemptAt'] != null
          ? DateTime.parse(json['lastAttemptAt'] as String)
          : null,
    );
  }
}

/// Queue statistics.
class QueueStats {
  /// Total operations in queue.
  final int total;

  /// Operations pending first attempt.
  final int pending;

  /// Operations being retried.
  final int retrying;

  /// Permanently failed operations.
  final int failed;

  const QueueStats({
    required this.total,
    required this.pending,
    required this.retrying,
    required this.failed,
  });

  @override
  String toString() =>
      'QueueStats(total: $total, pending: $pending, retrying: $retrying, failed: $failed)';
}

// Helper functions for JSON serialization of SyncOperation
// (JSON is used for queue persistence since it's more readable for debugging)

Map<String, dynamic> _syncOperationToJson(SyncOperation op) => {
  'opId': op.opId,
  'dbId': op.dbId,
  'deviceId': op.deviceId,
  'collection': op.collection,
  'entityId': op.entityId,
  'opType': op.opType.name,
  'entityVersion': op.entityVersion,
  'entityCbor': op.entityCbor != null ? base64Encode(op.entityCbor!) : null,
  'timestampMs': op.timestampMs,
};

SyncOperation _syncOperationFromJson(Map<String, dynamic> json) =>
    SyncOperation(
      opId: json['opId'] as int,
      dbId: json['dbId'] as String,
      deviceId: json['deviceId'] as String,
      collection: json['collection'] as String,
      entityId: json['entityId'] as String,
      opType: OperationType.values.byName(json['opType'] as String),
      entityVersion: json['entityVersion'] as int,
      entityCbor: json['entityCbor'] != null
          ? base64Decode(json['entityCbor'] as String)
          : null,
      timestampMs: json['timestampMs'] as int,
    );
