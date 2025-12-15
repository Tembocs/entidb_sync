/// Conflict Model
///
/// Represents a synchronization conflict when client and server have
/// concurrent modifications to the same entity.
library;

import 'dart:typed_data';

import 'package:meta/meta.dart';

import 'sync_operation.dart';

/// A synchronization conflict.
///
/// Occurs when a client attempts to push a change based on an outdated
/// entity version, while the server already has a newer version from
/// another client.
@immutable
class Conflict {
  /// Creates a conflict.
  const Conflict({
    required this.collection,
    required this.entityId,
    required this.clientOp,
    required this.serverState,
  });

  /// Collection name where conflict occurred.
  final String collection;

  /// Entity ID that has the conflict.
  final String entityId;

  /// The client's attempted operation.
  final SyncOperation clientOp;

  /// Current server state.
  final ServerState serverState;

  @override
  String toString() =>
      'Conflict('
      'collection: $collection, '
      'entityId: $entityId, '
      'clientVersion: ${clientOp.entityVersion}, '
      'serverVersion: ${serverState.entityVersion}'
      ')';
}

/// Current server state for conflict resolution.
@immutable
class ServerState {
  /// Creates a server state.
  const ServerState({
    required this.entityVersion,
    required this.entityCbor,
    this.lastModified,
  });

  /// Current entity version on server.
  final int entityVersion;

  /// Current entity data as CBOR.
  final Uint8List entityCbor;

  /// Last modification timestamp (informational).
  final DateTime? lastModified;
}
