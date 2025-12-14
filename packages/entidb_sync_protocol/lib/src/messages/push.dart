/// Push Messages
///
/// Protocol messages for pushing operations to server.
library;

import 'dart:typed_data';

import 'package:meta/meta.dart';

import '../cbor/decoders.dart';
import '../cbor/encoders.dart';
import '../models/conflict.dart';
import '../models/sync_operation.dart';

/// Push request sent by client to upload local operations.
///
/// POST /v1/push
@immutable
class PushRequest {
  /// Database identifier.
  final String dbId;

  /// Device identifier.
  final String deviceId;

  /// Operations to push to server.
  final List<SyncOperation> ops;

  const PushRequest({
    required this.dbId,
    required this.deviceId,
    required this.ops,
  });

  /// Serializes to CBOR bytes.
  Uint8List toBytes() {
    return encodeToCbor({
      'dbId': dbId,
      'deviceId': deviceId,
      'ops': [for (final op in ops) _syncOpToMap(op)],
    });
  }

  /// Deserializes from CBOR bytes.
  factory PushRequest.fromBytes(Uint8List bytes) {
    final map = decodeFromCbor(bytes);
    final opsList = map['ops'] as List;
    return PushRequest(
      dbId: map['dbId'] as String,
      deviceId: map['deviceId'] as String,
      ops: [
        for (final opMap in opsList)
          _syncOpFromMap(opMap as Map<String, dynamic>),
      ],
    );
  }

  @override
  String toString() =>
      'PushRequest(dbId: $dbId, deviceId: $deviceId, ops: ${ops.length})';
}

/// Push response from server.
@immutable
class PushResponse {
  /// Last operation ID that was successfully accepted.
  ///
  /// Operations with opId <= this value were accepted.
  /// Operations with opId > this value may have conflicts.
  final int acknowledgedUpToOpId;

  /// List of conflicts that need resolution.
  ///
  /// Empty if all operations were accepted.
  final List<Conflict> conflicts;

  const PushResponse({
    required this.acknowledgedUpToOpId,
    required this.conflicts,
  });

  /// Whether all operations were accepted without conflicts.
  bool get isFullyAccepted => conflicts.isEmpty;

  /// Serializes to CBOR bytes.
  Uint8List toBytes() {
    return encodeToCbor({
      'acknowledgedUpToOpId': acknowledgedUpToOpId,
      'conflicts': [for (final c in conflicts) _conflictToMap(c)],
    });
  }

  /// Deserializes from CBOR bytes.
  factory PushResponse.fromBytes(Uint8List bytes) {
    final map = decodeFromCbor(bytes);
    final conflictsList = map['conflicts'] as List;
    return PushResponse(
      acknowledgedUpToOpId: map['acknowledgedUpToOpId'] as int,
      conflicts: [
        for (final cMap in conflictsList)
          _conflictFromMap(cMap as Map<String, dynamic>),
      ],
    );
  }

  @override
  String toString() =>
      'PushResponse(acknowledgedUpToOpId: $acknowledgedUpToOpId, conflicts: ${conflicts.length})';
}

/// Converts SyncOperation to a Map for CBOR encoding.
Map<String, dynamic> _syncOpToMap(SyncOperation op) {
  return {
    'opId': op.opId,
    'dbId': op.dbId,
    'deviceId': op.deviceId,
    'collection': op.collection,
    'entityId': op.entityId,
    'opType': op.opType.name,
    'entityVersion': op.entityVersion,
    if (op.entityCbor != null) 'entityCbor': op.entityCbor,
    'timestampMs': op.timestampMs,
  };
}

/// Creates SyncOperation from a Map.
SyncOperation _syncOpFromMap(Map<String, dynamic> map) {
  return SyncOperation(
    opId: map['opId'] as int,
    dbId: map['dbId'] as String,
    deviceId: map['deviceId'] as String,
    collection: map['collection'] as String,
    entityId: map['entityId'] as String,
    opType: OperationType.values.firstWhere(
      (e) => e.name == (map['opType'] as String),
    ),
    entityVersion: map['entityVersion'] as int,
    entityCbor: map['entityCbor'] as Uint8List?,
    timestampMs: map['timestampMs'] as int,
  );
}

/// Converts Conflict to a Map for CBOR encoding.
Map<String, dynamic> _conflictToMap(Conflict conflict) {
  return {
    'collection': conflict.collection,
    'entityId': conflict.entityId,
    'clientOp': _syncOpToMap(conflict.clientOp),
    'serverState': {
      'entityVersion': conflict.serverState.entityVersion,
      'entityCbor': conflict.serverState.entityCbor,
      if (conflict.serverState.lastModified != null)
        'lastModified':
            conflict.serverState.lastModified!.millisecondsSinceEpoch,
    },
  };
}

/// Creates Conflict from a Map.
Conflict _conflictFromMap(Map<String, dynamic> map) {
  final serverStateMap = map['serverState'] as Map<String, dynamic>;
  return Conflict(
    collection: map['collection'] as String,
    entityId: map['entityId'] as String,
    clientOp: _syncOpFromMap(map['clientOp'] as Map<String, dynamic>),
    serverState: ServerState(
      entityVersion: serverStateMap['entityVersion'] as int,
      entityCbor: serverStateMap['entityCbor'] as Uint8List,
      lastModified: serverStateMap['lastModified'] != null
          ? DateTime.fromMillisecondsSinceEpoch(
              serverStateMap['lastModified'] as int)
          : null,
    ),
  );
}
