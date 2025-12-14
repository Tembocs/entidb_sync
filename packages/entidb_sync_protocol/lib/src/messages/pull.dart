/// Pull Messages
///
/// Protocol messages for pulling operations from server.
library;

import 'dart:typed_data';

import 'package:meta/meta.dart';

import '../cbor/decoders.dart';
import '../cbor/encoders.dart';
import '../models/sync_operation.dart';

/// Pull request sent by client to fetch server operations.
///
/// POST /v1/pull
@immutable
class PullRequest {
  /// Database identifier.
  final String dbId;

  /// Cursor position to start from (exclusive).
  ///
  /// Use 0 for initial sync, or the `nextCursor` from previous response.
  final int sinceCursor;

  /// Maximum number of operations to return.
  ///
  /// Server may return fewer operations if not available.
  final int limit;

  /// Optional collection filter.
  ///
  /// If provided, only operations for these collections are returned.
  final List<String>? collections;

  const PullRequest({
    required this.dbId,
    required this.sinceCursor,
    this.limit = 100,
    this.collections,
  });

  /// Serializes to CBOR bytes.
  Uint8List toBytes() {
    return encodeToCbor({
      'dbId': dbId,
      'sinceCursor': sinceCursor,
      'limit': limit,
      if (collections != null) 'collections': collections,
    });
  }

  /// Deserializes from CBOR bytes.
  factory PullRequest.fromBytes(Uint8List bytes) {
    final map = decodeFromCbor(bytes);
    return PullRequest(
      dbId: map['dbId'] as String,
      sinceCursor: map['sinceCursor'] as int,
      limit: map['limit'] as int? ?? 100,
      collections: (map['collections'] as List?)?.cast<String>(),
    );
  }

  @override
  String toString() =>
      'PullRequest(dbId: $dbId, sinceCursor: $sinceCursor, limit: $limit)';
}

/// Pull response from server containing operations.
@immutable
class PullResponse {
  /// List of operations since the requested cursor.
  final List<SyncOperation> ops;

  /// Cursor position for next pull request.
  ///
  /// Use this value as `sinceCursor` in the next request.
  final int nextCursor;

  /// Whether more operations are available.
  ///
  /// If true, client should make another pull request with `nextCursor`.
  final bool hasMore;

  const PullResponse({
    required this.ops,
    required this.nextCursor,
    required this.hasMore,
  });

  /// Serializes to CBOR bytes.
  Uint8List toBytes() {
    return encodeToCbor({
      'ops': [for (final op in ops) _syncOpToMap(op)],
      'nextCursor': nextCursor,
      'hasMore': hasMore,
    });
  }

  /// Deserializes from CBOR bytes.
  factory PullResponse.fromBytes(Uint8List bytes) {
    final map = decodeFromCbor(bytes);
    final opsList = map['ops'] as List;
    return PullResponse(
      ops: [
        for (final opMap in opsList)
          _syncOpFromMap(opMap as Map<String, dynamic>),
      ],
      nextCursor: map['nextCursor'] as int,
      hasMore: map['hasMore'] as bool,
    );
  }

  @override
  String toString() =>
      'PullResponse(ops: ${ops.length}, nextCursor: $nextCursor, hasMore: $hasMore)';
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
