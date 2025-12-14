/// EntiDB Persistence Service
///
/// Persistent sync service using EntiDB as the backing store.
///
/// Stores:
/// - Sync operations (oplog)
/// - Device registrations and cursors
/// - Database metadata
///
/// Collections:
/// - `_sync_ops`: Operation log entries
/// - `_sync_devices`: Device registration and cursor tracking
/// - `_sync_meta`: Server metadata (global cursor, config)
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:entidb/entidb.dart' hide OperationType;
import 'package:entidb_sync_protocol/entidb_sync_protocol.dart';
import 'package:synchronized/synchronized.dart';

/// Stored sync operation entity.
class StoredSyncOp implements Entity {
  @override
  final String? id;
  final int opId;
  final String dbId;
  final String deviceId;
  final String collection;
  final String entityId;
  final String opType;
  final int entityVersion;
  final String? entityCborBase64;
  final int timestampMs;
  final int clientOpId;

  const StoredSyncOp({
    this.id,
    required this.opId,
    required this.dbId,
    required this.deviceId,
    required this.collection,
    required this.entityId,
    required this.opType,
    required this.entityVersion,
    this.entityCborBase64,
    required this.timestampMs,
    required this.clientOpId,
  });

  @override
  Map<String, dynamic> toMap() => {
    'opId': opId,
    'dbId': dbId,
    'deviceId': deviceId,
    'collection': collection,
    'entityId': entityId,
    'opType': opType,
    'entityVersion': entityVersion,
    'entityCborBase64': entityCborBase64,
    'timestampMs': timestampMs,
    'clientOpId': clientOpId,
  };

  static StoredSyncOp fromMap(String id, Map<String, dynamic> map) {
    return StoredSyncOp(
      id: id,
      opId: map['opId'] as int,
      dbId: map['dbId'] as String,
      deviceId: map['deviceId'] as String,
      collection: map['collection'] as String,
      entityId: map['entityId'] as String,
      opType: map['opType'] as String,
      entityVersion: map['entityVersion'] as int,
      entityCborBase64: map['entityCborBase64'] as String?,
      timestampMs: map['timestampMs'] as int,
      clientOpId: map['clientOpId'] as int,
    );
  }

  /// Converts to a SyncOperation for the protocol.
  SyncOperation toSyncOperation() {
    return SyncOperation(
      opId: opId,
      dbId: dbId,
      deviceId: deviceId,
      collection: collection,
      entityId: entityId,
      opType: OperationType.values.byName(opType),
      entityVersion: entityVersion,
      entityCbor: entityCborBase64 != null
          ? base64Decode(entityCborBase64!)
          : null,
      timestampMs: timestampMs,
    );
  }
}

/// Stored device entity.
class StoredDevice implements Entity {
  @override
  final String? id;
  final String dbId;
  final String registeredAt;
  final String? lastSyncedAt;
  final int cursor;

  const StoredDevice({
    this.id,
    required this.dbId,
    required this.registeredAt,
    this.lastSyncedAt,
    required this.cursor,
  });

  @override
  Map<String, dynamic> toMap() => {
    'dbId': dbId,
    'registeredAt': registeredAt,
    'lastSyncedAt': lastSyncedAt,
    'cursor': cursor,
  };

  static StoredDevice fromMap(String id, Map<String, dynamic> map) {
    return StoredDevice(
      id: id,
      dbId: map['dbId'] as String,
      registeredAt: map['registeredAt'] as String,
      lastSyncedAt: map['lastSyncedAt'] as String?,
      cursor: map['cursor'] as int,
    );
  }

  StoredDevice copyWith({
    String? id,
    String? dbId,
    String? registeredAt,
    String? lastSyncedAt,
    int? cursor,
  }) {
    return StoredDevice(
      id: id ?? this.id,
      dbId: dbId ?? this.dbId,
      registeredAt: registeredAt ?? this.registeredAt,
      lastSyncedAt: lastSyncedAt ?? this.lastSyncedAt,
      cursor: cursor ?? this.cursor,
    );
  }
}

/// Stored metadata entity.
class StoredMeta implements Entity {
  @override
  final String? id;
  final int globalOpId;
  final String updatedAt;

  const StoredMeta({
    this.id,
    required this.globalOpId,
    required this.updatedAt,
  });

  @override
  Map<String, dynamic> toMap() => {
    'globalOpId': globalOpId,
    'updatedAt': updatedAt,
  };

  static StoredMeta fromMap(String id, Map<String, dynamic> map) {
    return StoredMeta(
      id: id,
      globalOpId: map['globalOpId'] as int,
      updatedAt: map['updatedAt'] as String,
    );
  }
}

/// EntiDB-backed sync service with persistent storage.
///
/// This implementation uses EntiDB to store the server's sync state,
/// including the operation log, device cursors, and metadata.
class EntiDBSyncService {
  final EntiDB _db;
  final Lock _lock = Lock();

  /// Global operation counter.
  int _globalOpId = 0;

  /// Collection references (initialized in [initialize]).
  late final Collection<StoredSyncOp> _opsCollection;
  late final Collection<StoredDevice> _devicesCollection;
  late final Collection<StoredMeta> _metaCollection;

  /// Internal collection names (prefixed with underscore).
  static const _opsCollectionName = '_sync_ops';
  static const _devicesCollectionName = '_sync_devices';
  static const _metaCollectionName = '_sync_meta';

  /// Creates a new EntiDB-backed sync service.
  ///
  /// - [db]: The EntiDB instance to use for storage.
  EntiDBSyncService({required EntiDB db}) : _db = db;

  /// Initializes the sync service.
  ///
  /// Creates collections and loads the global cursor from storage.
  /// Must be called before handling any requests.
  Future<void> initialize() async {
    await _lock.synchronized(() async {
      // Initialize collections
      _opsCollection = await _db.collection<StoredSyncOp>(
        _opsCollectionName,
        fromMap: StoredSyncOp.fromMap,
      );

      _devicesCollection = await _db.collection<StoredDevice>(
        _devicesCollectionName,
        fromMap: StoredDevice.fromMap,
      );

      _metaCollection = await _db.collection<StoredMeta>(
        _metaCollectionName,
        fromMap: StoredMeta.fromMap,
      );

      // Load global cursor from metadata
      final meta = await _metaCollection.get('global');
      if (meta != null) {
        _globalOpId = meta.globalOpId;
      }
    });
  }

  /// Processes a handshake request.
  ///
  /// Registers the device if new and returns the current server cursor.
  Future<HandshakeResponse> handleHandshake(HandshakeRequest request) async {
    return await _lock.synchronized(() async {
      // Get or create device record
      var device = await _devicesCollection.get(request.deviceId);

      if (device == null) {
        // Register new device
        device = StoredDevice(
          id: request.deviceId,
          dbId: request.dbId,
          registeredAt: DateTime.now().toIso8601String(),
          cursor: 0,
        );
        await _devicesCollection.insert(device);
      }

      return HandshakeResponse(
        serverCursor: _globalOpId,
        capabilities: const ServerCapabilities(
          pull: true,
          push: true,
          sse: false,
        ),
      );
    });
  }

  /// Processes a pull request.
  ///
  /// Returns operations since the client's cursor position.
  Future<PullResponse> handlePull(PullRequest request) async {
    return await _lock.synchronized(() async {
      // Query all operations
      final allOps = await _opsCollection.getAll();

      // Filter by cursor
      var ops = allOps.where((op) => op.opId > request.sinceCursor).toList();

      // Apply collection filter if provided
      if (request.collections != null) {
        ops = ops
            .where((op) => request.collections!.contains(op.collection))
            .toList();
      }

      // Sort by opId and limit
      ops.sort((a, b) => a.opId.compareTo(b.opId));
      if (ops.length > request.limit) {
        ops = ops.sublist(0, request.limit);
      }

      // Convert to SyncOperations
      final syncOps = ops.map((op) => op.toSyncOperation()).toList();

      // Calculate next cursor
      final nextCursor = syncOps.isEmpty
          ? request.sinceCursor
          : syncOps.last.opId;

      // Check if more operations available
      final hasMore = allOps.any((op) => op.opId > nextCursor);

      return PullResponse(
        ops: syncOps,
        nextCursor: nextCursor,
        hasMore: hasMore,
      );
    });
  }

  /// Processes a push request.
  ///
  /// Accepts client operations, detects conflicts, and updates the oplog.
  Future<PushResponse> handlePush(PushRequest request) async {
    return await _lock.synchronized(() async {
      final conflicts = <Conflict>[];
      int acknowledgedUpToOpId = 0;

      for (final clientOp in request.ops) {
        // Check for conflicts
        final conflict = await _detectConflict(clientOp);

        if (conflict != null) {
          conflicts.add(conflict);
          continue;
        }

        // Accept the operation
        _globalOpId++;

        final storedOp = StoredSyncOp(
          id: 'op_$_globalOpId',
          opId: _globalOpId,
          dbId: clientOp.dbId,
          deviceId: clientOp.deviceId,
          collection: clientOp.collection,
          entityId: clientOp.entityId,
          opType: clientOp.opType.name,
          entityVersion: clientOp.entityVersion,
          entityCborBase64: clientOp.entityCbor != null
              ? base64Encode(clientOp.entityCbor!)
              : null,
          timestampMs: DateTime.now().millisecondsSinceEpoch,
          clientOpId: clientOp.opId,
        );

        await _opsCollection.insert(storedOp);
        acknowledgedUpToOpId = clientOp.opId;
      }

      // Update global cursor in metadata
      final meta = StoredMeta(
        id: 'global',
        globalOpId: _globalOpId,
        updatedAt: DateTime.now().toIso8601String(),
      );

      // Try to update, if doesn't exist then insert
      final existingMeta = await _metaCollection.get('global');
      if (existingMeta != null) {
        await _metaCollection.update(meta);
      } else {
        await _metaCollection.insert(meta);
      }

      // Update device cursor
      if (acknowledgedUpToOpId > 0) {
        final device = await _devicesCollection.get(request.deviceId);
        if (device != null) {
          final updatedDevice = device.copyWith(
            cursor: _globalOpId,
            lastSyncedAt: DateTime.now().toIso8601String(),
          );
          await _devicesCollection.update(updatedDevice);
        }
      }

      return PushResponse(
        acknowledgedUpToOpId: acknowledgedUpToOpId,
        conflicts: conflicts,
      );
    });
  }

  /// Detects conflicts for an incoming operation.
  Future<Conflict?> _detectConflict(SyncOperation clientOp) async {
    // Find the latest server operation for this entity
    final allOps = await _opsCollection.getAll();

    final serverOps = allOps
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

    // Sort by opId descending to get latest
    serverOps.sort((a, b) => b.opId.compareTo(a.opId));
    final latestServerOp = serverOps.first;

    // Conflict if client version is older than server version
    if (clientOp.entityVersion <= latestServerOp.entityVersion) {
      final entityCbor = latestServerOp.entityCborBase64 != null
          ? base64Decode(latestServerOp.entityCborBase64!)
          : Uint8List(0);

      return Conflict(
        collection: clientOp.collection,
        entityId: clientOp.entityId,
        clientOp: clientOp,
        serverState: ServerState(
          entityVersion: latestServerOp.entityVersion,
          entityCbor: entityCbor,
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
  Future<int> get oplogSize async {
    final ops = await _opsCollection.getAll();
    return ops.length;
  }

  /// Gets statistics about the sync service.
  Future<Map<String, dynamic>> getStats() async {
    return await _lock.synchronized(() async {
      final ops = await _opsCollection.getAll();
      final devices = await _devicesCollection.getAll();

      return {
        'cursor': _globalOpId,
        'oplogSize': ops.length,
        'deviceCount': devices.length,
      };
    });
  }
}
