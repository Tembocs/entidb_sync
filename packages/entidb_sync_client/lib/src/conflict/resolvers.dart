/// Conflict Resolvers
///
/// Built-in conflict resolution strategies.
library;

import 'package:entidb_sync_protocol/entidb_sync_protocol.dart';

/// Strategy for resolving sync conflicts.
abstract class ConflictResolver {
  /// Resolves a conflict between client and server state.
  ///
  /// Returns the resolved operation to push, or null to accept server state.
  Future<SyncOperation?> resolve(Conflict conflict);
}

/// Server-wins strategy: Always accept the server's version.
///
/// This is the default and safest strategy.
class ServerWinsResolver implements ConflictResolver {
  const ServerWinsResolver();

  @override
  Future<SyncOperation?> resolve(Conflict conflict) async {
    // Return null to accept server state (discard client changes)
    return null;
  }
}

/// Client-wins strategy: Always use the client's version.
///
/// Warning: This can overwrite concurrent changes from other devices.
class ClientWinsResolver implements ConflictResolver {
  const ClientWinsResolver();

  @override
  Future<SyncOperation?> resolve(Conflict conflict) async {
    // Increment version and retry
    return SyncOperation(
      opId: conflict.clientOp.opId,
      dbId: conflict.clientOp.dbId,
      deviceId: conflict.clientOp.deviceId,
      collection: conflict.clientOp.collection,
      entityId: conflict.clientOp.entityId,
      opType: conflict.clientOp.opType,
      entityVersion: conflict.serverState.entityVersion + 1,
      entityCbor: conflict.clientOp.entityCbor,
      timestampMs: DateTime.now().millisecondsSinceEpoch,
    );
  }
}

/// Last-write-wins strategy: Use the most recent version based on timestamp.
class LastWriteWinsResolver implements ConflictResolver {
  const LastWriteWinsResolver();

  @override
  Future<SyncOperation?> resolve(Conflict conflict) async {
    final clientTime = conflict.clientOp.timestampMs;
    final serverTime =
        conflict.serverState.lastModified?.millisecondsSinceEpoch ?? 0;

    if (clientTime > serverTime) {
      // Client is newer, retry with updated version
      return SyncOperation(
        opId: conflict.clientOp.opId,
        dbId: conflict.clientOp.dbId,
        deviceId: conflict.clientOp.deviceId,
        collection: conflict.clientOp.collection,
        entityId: conflict.clientOp.entityId,
        opType: conflict.clientOp.opType,
        entityVersion: conflict.serverState.entityVersion + 1,
        entityCbor: conflict.clientOp.entityCbor,
        timestampMs: DateTime.now().millisecondsSinceEpoch,
      );
    }

    // Server is newer, accept server state
    return null;
  }
}

/// Custom resolver that uses a callback function.
class CustomResolver implements ConflictResolver {
  final Future<SyncOperation?> Function(Conflict conflict) _resolver;

  const CustomResolver(this._resolver);

  @override
  Future<SyncOperation?> resolve(Conflict conflict) => _resolver(conflict);
}

/// Composite resolver that tries multiple strategies in order.
class CompositeResolver implements ConflictResolver {
  final List<ConflictResolver> _resolvers;

  const CompositeResolver(this._resolvers);

  @override
  Future<SyncOperation?> resolve(Conflict conflict) async {
    for (final resolver in _resolvers) {
      final result = await resolver.resolve(conflict);
      if (result != null) {
        return result;
      }
    }
    return null;
  }
}
