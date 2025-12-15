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
  /// Creates a server-wins resolver.
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
  /// Creates a client-wins resolver.
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
  /// Creates a last-write-wins resolver.
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
  /// Creates a custom resolver with the specified callback.
  ///
  /// - [resolver]: Callback that resolves conflicts.
  const CustomResolver(this._resolver);

  final Future<SyncOperation?> Function(Conflict conflict) _resolver;

  @override
  Future<SyncOperation?> resolve(Conflict conflict) => _resolver(conflict);
}

/// Composite resolver that tries multiple strategies in order.
class CompositeResolver implements ConflictResolver {
  /// Creates a composite resolver with multiple strategies.
  ///
  /// - [resolvers]: List of resolvers to try in order.
  const CompositeResolver(this._resolvers);

  final List<ConflictResolver> _resolvers;

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
