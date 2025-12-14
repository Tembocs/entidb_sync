/// Sync Operation Model
///
/// Represents a logical replication event in the EntiDB sync protocol.
library;

import 'dart:typed_data';

import 'package:cbor/cbor.dart';
import 'package:meta/meta.dart';

/// Operation type enumeration.
enum OperationType {
  /// Insert or update operation.
  upsert,

  /// Delete operation.
  delete,
}

/// A single synchronization operation.
///
/// Represents a committed entity mutation that needs to be replicated
/// across EntiDB instances.
@immutable
class SyncOperation {
  /// Local operation ID (monotonic, per device).
  final int opId;

  /// Database identifier (globally unique).
  final String dbId;

  /// Device that originated this operation.
  final String deviceId;

  /// Collection name.
  final String collection;

  /// Entity ID.
  final String entityId;

  /// Operation type: upsert or delete.
  final OperationType opType;

  /// Entity version (for conflict detection).
  final int entityVersion;

  /// Raw CBOR-encoded entity data.
  ///
  /// For PUT operations: full entity data as CBOR.
  /// For DELETE operations: null.
  final Uint8List? entityCbor;

  /// Timestamp in milliseconds since epoch (informational only).
  final int timestampMs;

  const SyncOperation({
    required this.opId,
    required this.dbId,
    required this.deviceId,
    required this.collection,
    required this.entityId,
    required this.opType,
    required this.entityVersion,
    this.entityCbor,
    required this.timestampMs,
  });

  /// Serializes to CBOR bytes.
  Uint8List toBytes() {
    final map = <CborValue, CborValue>{
      CborString('opId'): CborInt(BigInt.from(opId)),
      CborString('dbId'): CborString(dbId),
      CborString('deviceId'): CborString(deviceId),
      CborString('collection'): CborString(collection),
      CborString('entityId'): CborString(entityId),
      CborString('opType'): CborString(opType.name),
      CborString('entityVersion'): CborInt(BigInt.from(entityVersion)),
      CborString('timestampMs'): CborInt(BigInt.from(timestampMs)),
    };

    if (entityCbor != null) {
      map[CborString('entityCbor')] = CborBytes(entityCbor!);
    }

    return Uint8List.fromList(cbor.encode(CborMap(map)));
  }

  /// Deserializes from CBOR bytes.
  factory SyncOperation.fromBytes(Uint8List bytes) {
    final cborValue = cbor.decode(bytes);
    if (cborValue is! CborMap) {
      throw FormatException('Invalid SyncOperation: expected CBOR map');
    }

    return SyncOperation(
      opId: (cborValue[CborString('opId')] as CborInt).toInt(),
      dbId: (cborValue[CborString('dbId')] as CborString).toString(),
      deviceId: (cborValue[CborString('deviceId')] as CborString).toString(),
      collection:
          (cborValue[CborString('collection')] as CborString).toString(),
      entityId: (cborValue[CborString('entityId')] as CborString).toString(),
      opType: OperationType.values.firstWhere(
        (e) =>
            e.name ==
            (cborValue[CborString('opType')] as CborString).toString(),
      ),
      entityVersion:
          (cborValue[CborString('entityVersion')] as CborInt).toInt(),
      entityCbor:
          (cborValue[CborString('entityCbor')] as CborBytes?)?.bytes != null
              ? Uint8List.fromList(
                  (cborValue[CborString('entityCbor')] as CborBytes).bytes)
              : null,
      timestampMs: (cborValue[CborString('timestampMs')] as CborInt).toInt(),
    );
  }

  @override
  String toString() => 'SyncOperation('
      'opId: $opId, '
      'collection: $collection, '
      'entityId: $entityId, '
      'opType: $opType, '
      'version: $entityVersion'
      ')';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SyncOperation &&
          runtimeType == other.runtimeType &&
          opId == other.opId &&
          dbId == other.dbId &&
          deviceId == other.deviceId;

  @override
  int get hashCode => Object.hash(opId, dbId, deviceId);
}
