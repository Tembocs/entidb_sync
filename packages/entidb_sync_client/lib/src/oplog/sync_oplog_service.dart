/// Sync Operation Log Service
///
/// Observes EntiDB's Write-Ahead Log (WAL) and transforms physical
/// transaction records into logical replication events (SyncOperations).
///
/// ## Purpose
///
/// EntiDB's WAL provides crash recovery via physical log records (page writes,
/// before/after images, LSNs). The sync oplog provides replication via logical
/// records (entity mutations, collection-scoped, globally ordered).
///
/// This service bridges the gap between:
/// - **Physical log** (WAL): Transaction durability, crash recovery
/// - **Logical log** (Oplog): Replication, synchronization
///
/// ## Architecture
///
/// ```
/// EntiDB (local)
///   └─ WAL (physical log)
///       └─ DataOperationPayload (CBOR)
///           │
///           ▼
///   SyncOplogService (observer)
///       └─ transforms to SyncOperation (logical log)
///           │
///           ▼
///   SyncClient
///       └─ HTTPS to server
/// ```
///
/// ## Key Concepts
///
/// - **Non-invasive:** Does not modify EntiDB core
/// - **Observable:** Exposes Stream<SyncOperation> for consumers
/// - **Cursor-based:** Tracks position in oplog for resumable sync
/// - **CBOR-native:** Reuses EntiDB's internal CBOR encoding
///
library;

import 'dart:async';
import 'dart:typed_data';

// TODO: Enable this import once protocol package dependencies are resolved
// For now, forward declare the SyncOperation class
// import 'package:entidb_sync_protocol/entidb_sync_protocol.dart';

/// Forward declaration - will be imported from protocol package
class SyncOperation {
  const SyncOperation();
}

/// Sync Operation Log Service
///
/// Observes EntiDB WAL and emits logical replication events.
///
/// Usage:
/// ```dart
/// final oplogService = SyncOplogService(
///   walPath: './mydb.wal',
///   dbId: 'production-db',
///   deviceId: 'android-device-1',
/// );
///
/// await oplogService.start();
///
/// oplogService.changeStream.listen((syncOp) {
///   print('Entity ${syncOp.entityId} changed in ${syncOp.collection}');
/// });
/// ```
abstract class SyncOplogService {
  /// Database identifier (globally unique).
  String get dbId;

  /// Device identifier (stable per client).
  String get deviceId;

  /// Stream of sync operations as they occur.
  ///
  /// Emits a [SyncOperation] for each committed entity mutation.
  /// Only emits after transaction commit (never for aborted transactions).
  Stream<SyncOperation> get changeStream;

  /// Current local operation ID.
  ///
  /// Monotonically increasing, unique per device.
  /// Used for idempotency and deduplication.
  int get currentOpId;

  /// Starts observing the WAL.
  ///
  /// Opens the WAL file and begins emitting operations.
  /// Resumes from the last known position if resumable state exists.
  ///
  /// Throws [StateError] if already started.
  /// Throws [WalNotFoundException] if WAL file doesn't exist.
  Future<void> start();

  /// Stops observing the WAL.
  ///
  /// Closes file handles and completes the change stream.
  /// Can be restarted with [start].
  Future<void> stop();

  /// Advances the oplog cursor.
  ///
  /// Acknowledges that operations up to [opId] have been successfully
  /// synchronized and can be compacted/garbage collected.
  ///
  /// - [opId]: The last operation ID that was successfully synced.
  Future<void> acknowledge(int opId);

  /// Gets all operations since a cursor position.
  ///
  /// Used for batch sync and catch-up scenarios.
  ///
  /// - [sinceOpId]: Start reading from this operation ID (exclusive).
  /// - [limit]: Maximum number of operations to return.
  ///
  /// Returns operations in ascending order by opId.
  Future<List<SyncOperation>> getOperationsSince({
    required int sinceOpId,
    int limit = 100,
  });

  /// Factory constructor for the default implementation.
  ///
  /// - [walPath]: Path to the EntiDB WAL file.
  /// - [dbId]: Database identifier.
  /// - [deviceId]: Device identifier.
  factory SyncOplogService({
    required String walPath,
    required String dbId,
    required String deviceId,
  }) {
    throw UnimplementedError(
      'SyncOplogService implementation not yet available. '
      'See packages/entidb_sync_client/lib/src/oplog/ for implementation.',
    );
  }
}

/// Exception thrown when WAL file is not found.
class WalNotFoundException implements Exception {
  final String path;
  final String message;

  WalNotFoundException(this.path, this.message);

  @override
  String toString() => 'WalNotFoundException: $message (path: $path)';
}

/// Transforms EntiDB WAL records into SyncOperations.
///
/// Internal helper for SyncOplogService.
abstract class OperationTransformer {
  /// Transforms a committed WAL record into a SyncOperation.
  ///
  /// - [walPayload]: The DataOperationPayload from EntiDB WAL.
  /// - [opId]: The local operation ID to assign.
  /// - [dbId]: Database identifier.
  /// - [deviceId]: Device identifier.
  ///
  /// Returns null if the record should be skipped (e.g., metadata operations).
  SyncOperation? transform({
    required Uint8List walPayload,
    required int opId,
    required String dbId,
    required String deviceId,
  });

  /// Extracts entity CBOR blob from WAL payload.
  ///
  /// WAL stores DataOperationPayload with beforeImage/afterImage.
  /// For sync, we only need the afterImage (for PUT) or beforeImage (for DELETE).
  Uint8List? extractEntityCbor(Uint8List walPayload, String opType);
}

/// Configuration for SyncOplogService.
class OplogConfig {
  /// Path to the WAL file.
  final String walPath;

  /// Database identifier.
  final String dbId;

  /// Device identifier.
  final String deviceId;

  /// Whether to persist oplog state for crash recovery.
  final bool persistState;

  /// Path to persist oplog state (cursor position, operation IDs).
  final String? statePath;

  /// Maximum operations to buffer before backpressure.
  final int maxBufferSize;

  const OplogConfig({
    required this.walPath,
    required this.dbId,
    required this.deviceId,
    this.persistState = true,
    this.statePath,
    this.maxBufferSize = 1000,
  });
}

/// Oplog state for persistence and recovery.
class OplogState {
  /// Last processed WAL LSN (Log Sequence Number).
  final int lastLsn;

  /// Last emitted operation ID.
  final int lastOpId;

  /// Timestamp of last processed operation.
  final DateTime lastProcessedAt;

  const OplogState({
    required this.lastLsn,
    required this.lastOpId,
    required this.lastProcessedAt,
  });

  /// Serializes to JSON for persistence.
  Map<String, dynamic> toJson() => {
    'lastLsn': lastLsn,
    'lastOpId': lastOpId,
    'lastProcessedAt': lastProcessedAt.toIso8601String(),
  };

  /// Deserializes from JSON.
  factory OplogState.fromJson(Map<String, dynamic> json) {
    return OplogState(
      lastLsn: json['lastLsn'] as int,
      lastOpId: json['lastOpId'] as int,
      lastProcessedAt: DateTime.parse(json['lastProcessedAt'] as String),
    );
  }
}
