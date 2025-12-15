/// Sync Engine
///
/// Main orchestrator for the pull-then-push sync cycle.
library;

import 'dart:async';

import 'package:entidb_sync_protocol/entidb_sync_protocol.dart';
import 'package:logging/logging.dart';

import '../transport/http_transport.dart';

/// Sync engine state.
enum SyncState {
  /// Not started.
  idle,

  /// Connecting to server.
  connecting,

  /// Pulling operations from server.
  pulling,

  /// Pushing operations to server.
  pushing,

  /// Sync completed successfully.
  synced,

  /// Sync failed with error.
  error,
}

/// Result of a sync cycle.
class SyncResult {
  /// Creates a sync result.
  ///
  /// - [state]: Final sync state.
  /// - [pulledCount]: Number of operations pulled.
  /// - [pushedCount]: Number of operations pushed.
  /// - [conflicts]: Conflicts encountered.
  /// - [error]: Error if sync failed.
  /// - [serverCursor]: New server cursor after sync.
  const SyncResult({
    required this.state,
    this.pulledCount = 0,
    this.pushedCount = 0,
    this.conflicts = const [],
    this.error,
    this.serverCursor = 0,
  });

  /// Final sync state.
  final SyncState state;

  /// Number of operations pulled.
  final int pulledCount;

  /// Number of operations pushed.
  final int pushedCount;

  /// Conflicts encountered.
  final List<Conflict> conflicts;

  /// Error if sync failed.
  final Object? error;

  /// New server cursor after sync.
  final int serverCursor;

  /// Whether sync completed successfully.
  bool get isSuccess => state == SyncState.synced;

  /// Whether there were conflicts.
  bool get hasConflicts => conflicts.isNotEmpty;

  @override
  String toString() =>
      'SyncResult(state: $state, pulled: $pulledCount, '
      'pushed: $pushedCount, conflicts: ${conflicts.length})';
}

/// Callback for applying pulled operations to local database.
typedef ApplyOperationCallback = Future<void> Function(SyncOperation op);

/// Callback for getting pending local operations to push.
typedef GetPendingOperationsCallback =
    Future<List<SyncOperation>> Function(int sinceOpId);

/// Callback for handling conflicts.
typedef ConflictHandler = Future<SyncOperation?> Function(Conflict conflict);

/// Sync engine orchestrates the pull-then-push sync cycle.
class SyncEngine {
  /// Creates a sync engine.
  ///
  /// - [transport]: HTTP transport for server communication.
  /// - [clientInfo]: Client info for handshake.
  SyncEngine({
    required SyncHttpTransport transport,
    required ClientInfo clientInfo,
  }) : _transport = transport,
       _clientInfo = clientInfo;

  final SyncHttpTransport _transport;
  final Logger _log = Logger('SyncEngine');

  /// Callback to apply pulled operations.
  ApplyOperationCallback? onApplyOperation;

  /// Callback to get pending operations.
  GetPendingOperationsCallback? onGetPendingOperations;

  /// Callback to handle conflicts.
  ConflictHandler? onConflict;

  /// Current sync state.
  SyncState _state = SyncState.idle;

  /// Gets the current sync state.
  SyncState get state => _state;

  /// Stream controller for state changes.
  final _stateController = StreamController<SyncState>.broadcast();

  /// Stream of state changes.
  Stream<SyncState> get stateStream => _stateController.stream;

  /// Current cursor positions.
  int _serverCursor = 0;
  int _localCursor = 0;

  /// Client info for handshake.
  final ClientInfo _clientInfo;

  /// Gets the current server cursor.
  int get serverCursor => _serverCursor;

  /// Gets the current local cursor.
  int get localCursor => _localCursor;

  /// Performs a full sync cycle (pull-then-push).
  Future<SyncResult> sync() async {
    if (_state == SyncState.pulling || _state == SyncState.pushing) {
      _log.warning('Sync already in progress');
      return SyncResult(state: _state);
    }

    int pulledCount = 0;
    int pushedCount = 0;
    final conflicts = <Conflict>[];

    try {
      // Connect/handshake
      _setState(SyncState.connecting);
      final handshakeResponse = await _transport.handshake(_clientInfo);
      _serverCursor = handshakeResponse.serverCursor;
      _log.info('Handshake complete. Server cursor: $_serverCursor');

      // Pull phase
      _setState(SyncState.pulling);
      pulledCount = await _pullAll();
      _log.info('Pulled $pulledCount operations');

      // Push phase
      _setState(SyncState.pushing);
      final pushResult = await _pushAll();
      pushedCount = pushResult.pushed;
      conflicts.addAll(pushResult.conflicts);
      _log.info(
        'Pushed $pushedCount operations, ${conflicts.length} conflicts',
      );

      _setState(SyncState.synced);
      return SyncResult(
        state: SyncState.synced,
        pulledCount: pulledCount,
        pushedCount: pushedCount,
        conflicts: conflicts,
        serverCursor: _serverCursor,
      );
    } catch (e, stack) {
      _log.severe('Sync failed', e, stack);
      _setState(SyncState.error);
      return SyncResult(
        state: SyncState.error,
        pulledCount: pulledCount,
        pushedCount: pushedCount,
        conflicts: conflicts,
        error: e,
        serverCursor: _serverCursor,
      );
    }
  }

  /// Pulls all available operations from server.
  Future<int> _pullAll() async {
    int totalPulled = 0;
    bool hasMore = true;

    while (hasMore) {
      final response = await _transport.pull(sinceCursor: _serverCursor);

      for (final op in response.ops) {
        if (onApplyOperation != null) {
          await onApplyOperation!(op);
        }
        totalPulled++;
      }

      _serverCursor = response.nextCursor;
      hasMore = response.hasMore;
    }

    return totalPulled;
  }

  /// Pushes all pending operations to server.
  Future<({int pushed, List<Conflict> conflicts})> _pushAll() async {
    if (onGetPendingOperations == null) {
      return (pushed: 0, conflicts: <Conflict>[]);
    }

    final pending = await onGetPendingOperations!(_localCursor);
    if (pending.isEmpty) {
      return (pushed: 0, conflicts: <Conflict>[]);
    }

    final response = await _transport.push(pending);
    final conflicts = <Conflict>[];

    // Handle conflicts
    for (final conflict in response.conflicts) {
      if (onConflict != null) {
        final resolved = await onConflict!(conflict);
        if (resolved != null) {
          // Retry with resolved operation
          await _transport.push([resolved]);
        }
      } else {
        conflicts.add(conflict);
      }
    }

    // Update local cursor
    if (response.acknowledgedUpToOpId > 0) {
      _localCursor = response.acknowledgedUpToOpId;
    }

    return (
      pushed: pending.length - response.conflicts.length,
      conflicts: conflicts,
    );
  }

  /// Sets the sync state and notifies listeners.
  void _setState(SyncState newState) {
    _state = newState;
    _stateController.add(newState);
  }

  /// Disposes resources.
  void dispose() {
    _stateController.close();
    _transport.close();
  }
}
