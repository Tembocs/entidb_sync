/// WAL Adapter
///
/// Abstraction layer for EntiDB WAL access.
///
/// This module provides a clean interface over EntiDB's internal WAL
/// implementation, isolating the sync client from breaking changes in
/// EntiDB's internal structure.
///
/// ## Purpose
///
/// EntiDB's WAL types are internal implementation details that may change
/// between versions. This adapter provides:
///
/// - **Stability:** Public API that won't break with EntiDB updates
/// - **Testability:** Easy to mock for unit tests
/// - **Flexibility:** Could support different WAL implementations
///
/// ## Usage
///
/// ```dart
/// final adapter = EntiDBWalAdapter(walPath: './mydb.wal');
/// await adapter.open();
///
/// await adapter.forEach((record) async {
///   print('Record LSN: ${record.lsn}, Type: ${record.type}');
///   return true; // Continue iteration
/// });
///
/// await adapter.close();
/// ```
library;

import 'dart:typed_data';

import 'package:meta/meta.dart';

// Internal EntiDB imports - isolated to this single file
// ignore: implementation_imports
import 'package:entidb/src/engine/wal/wal_constants.dart' as wal;
// ignore: implementation_imports
import 'package:entidb/src/engine/wal/wal_reader.dart' as wal;
// ignore: implementation_imports
import 'package:entidb/src/engine/wal/wal_record.dart' as wal;

/// WAL record type abstraction.
///
/// Maps to EntiDB's internal WalRecordType but provides a stable public API.
enum WalRecordType {
  /// Insert operation.
  insert,

  /// Update operation.
  update,

  /// Delete operation.
  delete,

  /// Transaction begin marker.
  beginTransaction,

  /// Transaction commit marker.
  commitTransaction,

  /// Transaction rollback marker.
  rollbackTransaction,

  /// Checkpoint marker.
  checkpoint,

  /// Unknown or unsupported record type.
  unknown,
}

/// Log Sequence Number abstraction.
///
/// Represents a position in the WAL for resumable reading.
@immutable
class WalLsn {
  /// Creates a WAL LSN from a numeric value.
  const WalLsn(this.value);

  /// The numeric LSN value.
  final int value;

  /// The first valid LSN (start of WAL).
  static const WalLsn first = WalLsn(0);

  @override
  bool operator ==(Object other) =>
      identical(this, other) || (other is WalLsn && other.value == value);

  @override
  int get hashCode => value.hashCode;

  @override
  String toString() => 'WalLsn($value)';
}

/// WAL record abstraction.
///
/// Represents a single record from EntiDB's Write-Ahead Log.
/// Contains all information needed for sync operation transformation.
@immutable
class WalRecord {
  /// Creates a WAL record.
  const WalRecord({
    required this.lsn,
    required this.type,
    required this.transactionId,
    required this.payload,
  });

  /// Log Sequence Number - unique position in the WAL.
  final WalLsn lsn;

  /// Record type (insert, update, delete, transaction markers).
  final WalRecordType type;

  /// Transaction ID this record belongs to.
  final int transactionId;

  /// Raw payload bytes (for data operations).
  final Uint8List payload;

  @override
  String toString() => 'WalRecord(lsn: $lsn, type: $type, txn: $transactionId)';
}

/// Abstract interface for WAL reading.
///
/// Allows different implementations for production vs. testing.
abstract class WalAdapter {
  /// Opens the WAL for reading.
  ///
  /// Must be called before any read operations.
  /// Throws [WalOpenException] if the WAL cannot be opened.
  Future<void> open();

  /// Closes the WAL reader.
  ///
  /// Releases file handles and resources.
  Future<void> close();

  /// Seeks to a specific LSN position.
  ///
  /// Subsequent reads will start from this position.
  /// Throws [WalSeekException] if the position is invalid.
  Future<void> seekToLsn(WalLsn lsn);

  /// Returns the current WAL length in bytes.
  int get length;

  /// Iterates over all records in the WAL.
  ///
  /// The callback receives each record and returns `true` to continue
  /// or `false` to stop iteration.
  Future<void> forEach(Future<bool> Function(WalRecord record) callback);
}

/// Production WAL adapter using EntiDB's internal WalReader.
///
/// This is the only place where internal EntiDB imports are used,
/// isolating version-specific code to a single file.
class EntiDBWalAdapter implements WalAdapter {
  /// Creates a WAL adapter for the specified file path.
  ///
  /// - [walPath]: Path to the EntiDB WAL file.
  EntiDBWalAdapter({required String walPath}) : _walPath = walPath;

  final String _walPath;
  wal.WalReader? _reader;

  @override
  Future<void> open() async {
    _reader = wal.WalReader(filePath: _walPath);
    try {
      await _reader!.open();
    } catch (e) {
      _reader = null;
      throw WalOpenException(_walPath, e.toString());
    }
  }

  @override
  Future<void> close() async {
    await _reader?.close();
    _reader = null;
  }

  @override
  Future<void> seekToLsn(WalLsn lsn) async {
    _checkOpen();
    try {
      await _reader!.seekToLsn(wal.Lsn(lsn.value));
    } catch (e) {
      throw WalSeekException(lsn, e.toString());
    }
  }

  @override
  int get length {
    _checkOpen();
    return _reader!.length;
  }

  @override
  Future<void> forEach(Future<bool> Function(WalRecord record) callback) async {
    _checkOpen();
    await _reader!.forEach((internalRecord) async {
      final record = _convertRecord(internalRecord);
      return callback(record);
    });
  }

  void _checkOpen() {
    if (_reader == null) {
      throw StateError('WalAdapter is not open. Call open() first.');
    }
  }

  /// Converts an internal EntiDB WAL record to our abstraction.
  WalRecord _convertRecord(wal.WalRecord internalRecord) {
    return WalRecord(
      lsn: WalLsn(internalRecord.lsn.value),
      type: _convertType(internalRecord.type),
      transactionId: internalRecord.transactionId,
      payload: internalRecord.payload,
    );
  }

  /// Converts internal record type to our enum.
  WalRecordType _convertType(wal.WalRecordType internalType) {
    switch (internalType) {
      case wal.WalRecordType.insert:
        return WalRecordType.insert;
      case wal.WalRecordType.update:
        return WalRecordType.update;
      case wal.WalRecordType.delete:
        return WalRecordType.delete;
      case wal.WalRecordType.beginTransaction:
        return WalRecordType.beginTransaction;
      case wal.WalRecordType.commitTransaction:
        return WalRecordType.commitTransaction;
      case wal.WalRecordType.checkpoint:
        return WalRecordType.checkpoint;
      default:
        return WalRecordType.unknown;
    }
  }
}

/// Exception thrown when WAL cannot be opened.
class WalOpenException implements Exception {
  /// Creates a WAL open exception.
  const WalOpenException(this.path, this.message);

  /// Path to the WAL file.
  final String path;

  /// Error message.
  final String message;

  @override
  String toString() => 'WalOpenException: $message (path: $path)';
}

/// Exception thrown when WAL seek fails.
class WalSeekException implements Exception {
  /// Creates a WAL seek exception.
  const WalSeekException(this.targetLsn, this.message);

  /// Target LSN.
  final WalLsn targetLsn;

  /// Error message.
  final String message;

  @override
  String toString() => 'WalSeekException: $message (target: $targetLsn)';
}

/// Data operation payload abstraction.
///
/// Wraps EntiDB's internal DataOperationPayload for stable API access.
@immutable
class DataOperationPayload {
  /// Creates a data operation payload.
  const DataOperationPayload({
    required this.collectionName,
    required this.entityId,
    this.afterImage,
    this.beforeImage,
  });

  /// Parses a DataOperationPayload from raw WAL bytes.
  ///
  /// Uses EntiDB's internal deserialization.
  factory DataOperationPayload.fromBytes(Uint8List bytes) {
    final internal = wal.DataOperationPayload.fromBytes(bytes);
    return DataOperationPayload(
      collectionName: internal.collectionName,
      entityId: internal.entityId,
      afterImage: internal.afterImage,
      beforeImage: internal.beforeImage,
    );
  }

  /// Creates an insert payload for testing.
  ///
  /// Insert operations have afterImage but no beforeImage.
  factory DataOperationPayload.insert({
    required String collectionName,
    required String entityId,
    required Map<String, dynamic> data,
  }) {
    return DataOperationPayload(
      collectionName: collectionName,
      entityId: entityId,
      afterImage: data,
    );
  }

  /// Creates an update payload for testing.
  ///
  /// Update operations have both beforeImage and afterImage.
  factory DataOperationPayload.update({
    required String collectionName,
    required String entityId,
    required Map<String, dynamic> before,
    required Map<String, dynamic> after,
  }) {
    return DataOperationPayload(
      collectionName: collectionName,
      entityId: entityId,
      beforeImage: before,
      afterImage: after,
    );
  }

  /// Creates a delete payload for testing.
  ///
  /// Delete operations have beforeImage but no afterImage.
  factory DataOperationPayload.delete({
    required String collectionName,
    required String entityId,
    required Map<String, dynamic> data,
  }) {
    return DataOperationPayload(
      collectionName: collectionName,
      entityId: entityId,
      beforeImage: data,
    );
  }

  /// Collection name.
  final String collectionName;

  /// Entity ID.
  final String entityId;

  /// After image (entity state after the operation).
  ///
  /// Null for delete operations.
  final Map<String, dynamic>? afterImage;

  /// Before image (entity state before the operation).
  ///
  /// Null for insert operations.
  final Map<String, dynamic>? beforeImage;

  /// Serializes to bytes for testing.
  ///
  /// Creates a simple CBOR representation.
  Uint8List toBytes() {
    // Create a simple CBOR structure matching EntiDB format
    // This is for testing - real WAL records are created by EntiDB
    // Use CBOR encoding
    return wal.DataOperationPayload(
      collectionName: collectionName,
      entityId: entityId,
      afterImage: afterImage,
      beforeImage: beforeImage,
    ).toBytes();
  }
}
