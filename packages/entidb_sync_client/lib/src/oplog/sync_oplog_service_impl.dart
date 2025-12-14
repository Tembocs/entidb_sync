/// Sync Operation Log Service Implementation
///
/// Concrete implementation of SyncOplogService that observes EntiDB WAL
/// and emits logical replication events.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:cbor/cbor.dart';
import 'package:entidb/src/engine/wal/wal_constants.dart';
import 'package:entidb/src/engine/wal/wal_reader.dart';
import 'package:entidb/src/engine/wal/wal_record.dart';
import 'package:entidb_sync_protocol/entidb_sync_protocol.dart';

import 'sync_oplog_service.dart';

/// Default implementation of [SyncOplogService].
///
/// Observes the EntiDB WAL file and transforms physical log records
/// into logical [SyncOperation] events for synchronization.
class SyncOplogServiceImpl implements SyncOplogService {
  final OplogConfig _config;
  final StreamController<SyncOperation> _changeController;
  final OperationTransformer _transformer;

  int _currentOpId = 0;
  bool _isRunning = false;
  OplogState? _state;
  Timer? _pollTimer;
  int _lastProcessedLsn = 0;

  /// Pending operations buffer (not yet acknowledged).
  final List<SyncOperation> _pendingOps = [];

  /// Tracks committed transactions for filtering.
  final Set<int> _committedTransactions = {};

  SyncOplogServiceImpl({
    required OplogConfig config,
    OperationTransformer? transformer,
  }) : _config = config,
       _transformer = transformer ?? OperationTransformerImpl(),
       _changeController = StreamController<SyncOperation>.broadcast();

  @override
  String get dbId => _config.dbId;

  @override
  String get deviceId => _config.deviceId;

  @override
  Stream<SyncOperation> get changeStream => _changeController.stream;

  @override
  int get currentOpId => _currentOpId;

  @override
  Future<void> start() async {
    if (_isRunning) {
      throw StateError('SyncOplogService is already running');
    }

    // Check WAL file exists
    final walFile = File(_config.walPath);
    if (!await walFile.exists()) {
      throw WalNotFoundException(
        _config.walPath,
        'WAL file not found at specified path',
      );
    }

    // Load persisted state if available
    await _loadState();

    _isRunning = true;

    // Start WAL observation with polling
    // EntiDB WAL doesn't support file watching, so we poll periodically
    await _processNewWalRecords();
    _startPolling();
  }

  @override
  Future<void> stop() async {
    if (!_isRunning) return;

    _isRunning = false;
    _pollTimer?.cancel();
    _pollTimer = null;
    await _saveState();
  }

  @override
  Future<void> acknowledge(int opId) async {
    // Remove acknowledged operations from pending buffer
    _pendingOps.removeWhere((op) => op.opId <= opId);

    // Update state
    if (_state != null) {
      _state = OplogState(
        lastLsn: _state!.lastLsn,
        lastOpId: opId,
        lastProcessedAt: DateTime.now(),
      );
      await _saveState();
    }
  }

  @override
  Future<List<SyncOperation>> getOperationsSince({
    required int sinceOpId,
    int limit = 100,
  }) async {
    // Return operations from pending buffer that are after sinceOpId
    final ops = _pendingOps
        .where((op) => op.opId > sinceOpId)
        .take(limit)
        .toList();

    return ops;
  }

  /// Starts polling for new WAL records.
  void _startPolling() {
    // Poll every 100ms for new WAL records
    _pollTimer = Timer.periodic(
      const Duration(milliseconds: 100),
      (_) => _processNewWalRecords(),
    );
  }

  /// Processes new WAL records and emits sync operations.
  Future<void> _processNewWalRecords() async {
    if (!_isRunning) return;

    try {
      final walFile = File(_config.walPath);
      if (!await walFile.exists()) return;

      final reader = WalReader(filePath: _config.walPath);

      try {
        await reader.open();
      } catch (e) {
        // WAL file might be in use or corrupted, retry later
        return;
      }

      try {
        // First pass: identify committed transactions
        await _analyzeTransactions(reader);

        // Seek to last processed position
        if (_lastProcessedLsn > 0 && _lastProcessedLsn < reader.length) {
          try {
            await reader.seekToLsn(Lsn(_lastProcessedLsn));
          } catch (e) {
            // If seek fails, start from beginning
            // (but skip already processed records)
          }
        }

        // Second pass: emit operations from committed transactions
        await _emitCommittedOperations(reader);
      } finally {
        await reader.close();
      }
    } catch (e) {
      // Log error but continue polling
      // In production, use proper logging
    }
  }

  /// Analyzes WAL to identify committed transactions.
  Future<void> _analyzeTransactions(WalReader reader) async {
    _committedTransactions.clear();

    await reader.forEach((record) async {
      if (record.type == WalRecordType.commitTransaction) {
        _committedTransactions.add(record.transactionId);
      }
      return true;
    });

    // Reset reader position
    await reader.seekToLsn(Lsn.first);
  }

  /// Emits operations from committed transactions.
  Future<void> _emitCommittedOperations(WalReader reader) async {
    await reader.forEach((record) async {
      // Skip if already processed
      if (record.lsn.value <= _lastProcessedLsn) {
        return true;
      }

      // Only process data operations from committed transactions
      if (!_committedTransactions.contains(record.transactionId)) {
        return true;
      }

      // Process insert, update, delete operations
      if (record.type == WalRecordType.insert ||
          record.type == WalRecordType.update ||
          record.type == WalRecordType.delete) {
        final syncOp = _transformer.transform(
          walPayload: record.payload,
          opId: nextOpId(),
          dbId: _config.dbId,
          deviceId: _config.deviceId,
        );

        if (syncOp != null) {
          emitOperation(syncOp);
        }
      }

      _lastProcessedLsn = record.lsn.value;
      return true;
    });

    // Update persisted state
    if (_state == null || _lastProcessedLsn > _state!.lastLsn) {
      _state = OplogState(
        lastLsn: _lastProcessedLsn,
        lastOpId: _currentOpId,
        lastProcessedAt: DateTime.now(),
      );
      await _saveState();
    }
  }

  /// Emits a sync operation.
  ///
  /// Called internally when a WAL record is processed.
  void emitOperation(SyncOperation op) {
    if (!_isRunning) return;

    _pendingOps.add(op);

    // Apply backpressure if buffer is full
    if (_pendingOps.length > _config.maxBufferSize) {
      _pendingOps.removeAt(0); // Remove oldest
    }

    _changeController.add(op);
  }

  /// Generates the next operation ID.
  int nextOpId() {
    _currentOpId++;
    return _currentOpId;
  }

  /// Loads persisted state from disk.
  Future<void> _loadState() async {
    if (!_config.persistState || _config.statePath == null) return;

    final stateFile = File(_config.statePath!);
    if (await stateFile.exists()) {
      try {
        final json = jsonDecode(await stateFile.readAsString());
        _state = OplogState.fromJson(json as Map<String, dynamic>);
        _currentOpId = _state!.lastOpId;
        _lastProcessedLsn = _state!.lastLsn;
      } catch (e) {
        // Ignore corrupt state file, start fresh
        _state = null;
      }
    }
  }

  /// Saves state to disk for crash recovery.
  Future<void> _saveState() async {
    if (!_config.persistState || _config.statePath == null) return;
    if (_state == null) return;

    final stateFile = File(_config.statePath!);
    await stateFile.writeAsString(jsonEncode(_state!.toJson()));
  }

  /// Disposes resources.
  Future<void> dispose() async {
    await stop();
    await _changeController.close();
  }
}

/// Default implementation of [OperationTransformer].
///
/// Transforms EntiDB WAL DataOperationPayload into SyncOperation.
class OperationTransformerImpl implements OperationTransformer {
  @override
  SyncOperation? transform({
    required Uint8List walPayload,
    required int opId,
    required String dbId,
    required String deviceId,
  }) {
    try {
      // Parse the DataOperationPayload from EntiDB's WAL
      final payload = DataOperationPayload.fromBytes(walPayload);

      // Skip internal/system collections (e.g., starting with '_')
      if (payload.collectionName.startsWith('_')) {
        return null;
      }

      // Determine operation type
      final opType = _determineOperationType(payload);

      // Extract entity data
      final entityCbor = extractEntityCbor(walPayload, opType.name);

      // Entity version: use timestamp as version for conflict detection
      // In a real implementation, this would come from the entity's version field
      final entityVersion = DateTime.now().millisecondsSinceEpoch;

      return SyncOperation(
        opId: opId,
        dbId: dbId,
        deviceId: deviceId,
        collection: payload.collectionName,
        entityId: payload.entityId,
        opType: opType,
        entityVersion: entityVersion,
        entityCbor: entityCbor,
        timestampMs: DateTime.now().millisecondsSinceEpoch,
      );
    } catch (e) {
      // If parsing fails, skip this record
      return null;
    }
  }

  /// Determines the operation type from the WAL payload.
  OperationType _determineOperationType(DataOperationPayload payload) {
    // If there's no afterImage, it's a delete
    if (payload.afterImage == null) {
      return OperationType.delete;
    }
    // Otherwise it's an upsert (insert or update)
    return OperationType.upsert;
  }

  @override
  Uint8List? extractEntityCbor(Uint8List walPayload, String opType) {
    try {
      final payload = DataOperationPayload.fromBytes(walPayload);

      if (opType == 'delete') {
        // For deletes, we don't include entity data
        return null;
      }

      // For upserts, encode the afterImage as CBOR
      final afterImage = payload.afterImage;
      if (afterImage == null) {
        return null;
      }

      // Encode the entity data to CBOR
      return Uint8List.fromList(cbor.encode(_mapToCbor(afterImage)));
    } catch (e) {
      return null;
    }
  }

  /// Converts a Map to CborValue.
  CborValue _mapToCbor(Map<String, dynamic> map) {
    return CborMap({
      for (final entry in map.entries)
        CborString(entry.key): _valueToCbor(entry.value),
    });
  }

  /// Converts a dynamic value to CborValue.
  CborValue _valueToCbor(dynamic value) {
    if (value == null) return const CborNull();
    if (value is bool) return CborBool(value);
    if (value is int) return CborSmallInt(value);
    if (value is double) return CborFloat(value);
    if (value is String) return CborString(value);
    if (value is Uint8List) return CborBytes(value);
    if (value is List) return CborList(value.map(_valueToCbor).toList());
    if (value is Map<String, dynamic>) return _mapToCbor(value);
    return CborString(value.toString());
  }
}
