/// Sync Manager
///
/// Integrates all sync components into a cohesive automatic sync system.
///
/// The SyncManager connects:
/// - [SyncOplogService] for WAL observation (local change detection)
/// - [OfflineQueue] for pending operation storage
/// - [SyncEngine] for pull-then-push synchronization
///
/// ## Usage
///
/// ```dart
/// final syncManager = SyncManager(
///   oplogService: oplogService,
///   offlineQueue: offlineQueue,
///   syncEngine: syncEngine,
/// );
///
/// await syncManager.start();
///
/// // Sync happens automatically when local changes occur
/// // Or trigger manually:
/// await syncManager.syncNow();
/// ```
library;

import 'dart:async';

import 'package:entidb_sync_protocol/entidb_sync_protocol.dart';
import 'package:logging/logging.dart';

import '../oplog/sync_oplog_service.dart';
import '../queue/offline_queue.dart';
import 'sync_engine.dart';

/// Configuration for automatic sync behavior.
class SyncManagerConfig {
  /// Creates sync manager configuration.
  ///
  /// - [debounceDelay]: Debounce duration before triggering sync.
  /// - [periodicSyncInterval]: Interval for periodic sync attempts.
  /// - [maxBatchSize]: Maximum operations to sync per push cycle.
  /// - [syncOnStart]: Whether to sync immediately on start.
  /// - [autoRetry]: Whether to automatically retry failed syncs.
  /// - [retryDelay]: Delay before retrying after a failed sync.
  /// - [maxRetryAttempts]: Maximum retry attempts before giving up.
  const SyncManagerConfig({
    this.debounceDelay = const Duration(milliseconds: 500),
    this.periodicSyncInterval = const Duration(minutes: 5),
    this.maxBatchSize = 100,
    this.syncOnStart = true,
    this.autoRetry = true,
    this.retryDelay = const Duration(seconds: 5),
    this.maxRetryAttempts = 3,
  });

  /// Creates configuration for real-time sync (minimal debounce).
  const SyncManagerConfig.realtime()
    : debounceDelay = const Duration(milliseconds: 100),
      periodicSyncInterval = const Duration(minutes: 1),
      maxBatchSize = 50,
      syncOnStart = true,
      autoRetry = true,
      retryDelay = const Duration(seconds: 2),
      maxRetryAttempts = 5;

  /// Creates configuration for battery-conscious sync.
  const SyncManagerConfig.batterySaver()
    : debounceDelay = const Duration(seconds: 5),
      periodicSyncInterval = const Duration(minutes: 15),
      maxBatchSize = 200,
      syncOnStart = true,
      autoRetry = true,
      retryDelay = const Duration(seconds: 30),
      maxRetryAttempts = 3;

  /// Debounce duration before triggering sync after local changes.
  ///
  /// Prevents excessive sync cycles during rapid local edits.
  final Duration debounceDelay;

  /// Interval for periodic sync attempts.
  ///
  /// Set to [Duration.zero] to disable periodic sync.
  final Duration periodicSyncInterval;

  /// Maximum operations to sync per push cycle.
  final int maxBatchSize;

  /// Whether to sync immediately on start.
  final bool syncOnStart;

  /// Whether to automatically retry failed syncs.
  final bool autoRetry;

  /// Delay before retrying after a failed sync.
  final Duration retryDelay;

  /// Maximum retry attempts before giving up.
  final int maxRetryAttempts;
}

/// State of the sync manager.
enum SyncManagerState {
  /// Not started.
  stopped,

  /// Running and ready to sync.
  running,

  /// Currently syncing.
  syncing,

  /// Paused (e.g., no network).
  paused,

  /// Error state (requires restart).
  error,
}

/// Statistics about sync operations.
class SyncStats {
  /// Creates sync statistics.
  ///
  /// - [totalPushed]: Total operations synced (pushed).
  /// - [totalPulled]: Total operations received (pulled).
  /// - [totalConflicts]: Total conflicts encountered.
  /// - [syncCycles]: Number of sync cycles completed.
  /// - [failedAttempts]: Number of failed sync attempts.
  /// - [lastSyncTime]: Last successful sync time.
  /// - [pendingCount]: Current pending operations count.
  const SyncStats({
    this.totalPushed = 0,
    this.totalPulled = 0,
    this.totalConflicts = 0,
    this.syncCycles = 0,
    this.failedAttempts = 0,
    this.lastSyncTime,
    this.pendingCount = 0,
  });

  /// Total operations synced (pushed).
  final int totalPushed;

  /// Total operations received (pulled).
  final int totalPulled;

  /// Total conflicts encountered.
  final int totalConflicts;

  /// Number of sync cycles completed.
  final int syncCycles;

  /// Number of failed sync attempts.
  final int failedAttempts;

  /// Last successful sync time.
  final DateTime? lastSyncTime;

  /// Current pending operations count.
  final int pendingCount;

  /// Creates a copy of this [SyncStats] with the given fields replaced.
  SyncStats copyWith({
    int? totalPushed,
    int? totalPulled,
    int? totalConflicts,
    int? syncCycles,
    int? failedAttempts,
    DateTime? lastSyncTime,
    int? pendingCount,
  }) {
    return SyncStats(
      totalPushed: totalPushed ?? this.totalPushed,
      totalPulled: totalPulled ?? this.totalPulled,
      totalConflicts: totalConflicts ?? this.totalConflicts,
      syncCycles: syncCycles ?? this.syncCycles,
      failedAttempts: failedAttempts ?? this.failedAttempts,
      lastSyncTime: lastSyncTime ?? this.lastSyncTime,
      pendingCount: pendingCount ?? this.pendingCount,
    );
  }

  @override
  String toString() =>
      'SyncStats(pushed: $totalPushed, pulled: $totalPulled, '
      'conflicts: $totalConflicts, cycles: $syncCycles, pending: $pendingCount)';
}

/// Manages automatic synchronization between local EntiDB and sync server.
///
/// Integrates WAL observation, offline queue, and sync engine into a
/// unified automatic sync system.
class SyncManager {
  /// Creates a sync manager with the given components.
  ///
  /// - [oplogService]: Observes local WAL for changes.
  /// - [offlineQueue]: Stores pending operations.
  /// - [syncEngine]: Handles server communication.
  /// - [config]: Automatic sync configuration.
  SyncManager({
    required SyncOplogService oplogService,
    required OfflineQueue offlineQueue,
    required SyncEngine syncEngine,
    SyncManagerConfig config = const SyncManagerConfig(),
  }) : _oplogService = oplogService,
       _offlineQueue = offlineQueue,
       _syncEngine = syncEngine,
       _config = config {
    // Wire up the sync engine callbacks
    _syncEngine.onGetPendingOperations = _getPendingOperations;
  }

  final SyncOplogService _oplogService;
  final OfflineQueue _offlineQueue;
  final SyncEngine _syncEngine;
  final SyncManagerConfig _config;
  final Logger _log = Logger('SyncManager');

  /// Current state.
  SyncManagerState _state = SyncManagerState.stopped;

  /// Gets the current state.
  SyncManagerState get state => _state;

  /// Sync statistics.
  SyncStats _stats = const SyncStats();

  /// Gets the sync statistics.
  SyncStats get stats => _stats;

  /// State change stream.
  final _stateController = StreamController<SyncManagerState>.broadcast();

  /// Stream of state changes.
  Stream<SyncManagerState> get stateStream => _stateController.stream;

  /// Sync result stream.
  final _syncResultController = StreamController<SyncResult>.broadcast();

  /// Stream of sync results.
  Stream<SyncResult> get syncResultStream => _syncResultController.stream;

  /// Subscriptions.
  StreamSubscription<SyncOperation>? _oplogSubscription;
  StreamSubscription<SyncState>? _engineSubscription;
  Timer? _debounceTimer;
  Timer? _periodicTimer;
  Timer? _retryTimer;

  /// Retry tracking.
  int _retryAttempts = 0;

  /// Lock to prevent concurrent syncs.
  bool _syncInProgress = false;

  /// Starts automatic synchronization.
  ///
  /// - Starts WAL observation.
  /// - Opens the offline queue.
  /// - Subscribes to local change events.
  /// - Optionally triggers initial sync.
  ///
  /// Throws [StateError] if already started.
  Future<void> start() async {
    if (_state == SyncManagerState.running ||
        _state == SyncManagerState.syncing) {
      throw StateError('SyncManager is already running');
    }

    _log.info('Starting SyncManager');

    try {
      // Open queue if not already open
      if (!_offlineQueue.isOpen) {
        await _offlineQueue.open();
      }

      // Start WAL observation
      await _oplogService.start();

      // Subscribe to local changes
      _oplogSubscription = _oplogService.changeStream.listen(_onLocalChange);

      // Subscribe to sync engine state
      _engineSubscription = _syncEngine.stateStream.listen(_onSyncStateChange);

      // Start periodic sync if configured
      if (_config.periodicSyncInterval > Duration.zero) {
        _periodicTimer = Timer.periodic(
          _config.periodicSyncInterval,
          (_) => _triggerSync(),
        );
      }

      _setState(SyncManagerState.running);
      _log.info('SyncManager started');

      // Initial sync if configured
      if (_config.syncOnStart) {
        await syncNow();
      }
    } catch (e, stack) {
      _log.severe('Failed to start SyncManager', e, stack);
      _setState(SyncManagerState.error);
      rethrow;
    }
  }

  /// Stops automatic synchronization.
  ///
  /// - Cancels all timers and subscriptions.
  /// - Stops WAL observation.
  /// - Closes the offline queue.
  Future<void> stop() async {
    if (_state == SyncManagerState.stopped) return;

    _log.info('Stopping SyncManager');

    // Cancel timers
    _debounceTimer?.cancel();
    _periodicTimer?.cancel();
    _retryTimer?.cancel();

    // Cancel subscriptions
    await _oplogSubscription?.cancel();
    await _engineSubscription?.cancel();

    // Stop WAL observation
    await _oplogService.stop();

    // Close queue
    await _offlineQueue.close();

    _setState(SyncManagerState.stopped);
    _log.info('SyncManager stopped');
  }

  /// Pauses automatic synchronization.
  ///
  /// Local changes are still queued, but sync cycles are not triggered.
  /// Call [resume] to continue syncing.
  void pause() {
    if (_state != SyncManagerState.running &&
        _state != SyncManagerState.syncing) {
      return;
    }

    _log.info('Pausing SyncManager');
    _debounceTimer?.cancel();
    _periodicTimer?.cancel();
    _setState(SyncManagerState.paused);
  }

  /// Resumes automatic synchronization after [pause].
  void resume() {
    if (_state != SyncManagerState.paused) return;

    _log.info('Resuming SyncManager');

    // Restart periodic sync
    if (_config.periodicSyncInterval > Duration.zero) {
      _periodicTimer = Timer.periodic(
        _config.periodicSyncInterval,
        (_) => _triggerSync(),
      );
    }

    _setState(SyncManagerState.running);

    // Trigger sync if there are pending operations
    if (_offlineQueue.isNotEmpty) {
      _triggerSync();
    }
  }

  /// Triggers a sync cycle immediately.
  ///
  /// Returns the sync result when complete.
  Future<SyncResult> syncNow() async {
    if (_syncInProgress) {
      _log.warning('Sync already in progress');
      return const SyncResult(state: SyncState.idle);
    }

    return _performSync();
  }

  /// Gets pending operation count.
  int get pendingCount => _offlineQueue.length;

  /// Whether there are pending operations.
  bool get hasPendingChanges => _offlineQueue.isNotEmpty;

  /// Called when a local change is detected from WAL.
  void _onLocalChange(SyncOperation operation) {
    _log.fine(
      'Local change detected: ${operation.opType} '
      '${operation.collection}/${operation.entityId}',
    );

    // Add to offline queue
    _offlineQueue.enqueue(operation);

    // Update stats
    _stats = _stats.copyWith(pendingCount: _offlineQueue.length);

    // Debounce sync trigger
    _debounceTimer?.cancel();
    _debounceTimer = Timer(_config.debounceDelay, _triggerSync);
  }

  /// Called when sync engine state changes.
  void _onSyncStateChange(SyncState engineState) {
    switch (engineState) {
      case SyncState.idle:
        if (_state == SyncManagerState.syncing) {
          _setState(SyncManagerState.running);
        }
      case SyncState.connecting:
      case SyncState.pulling:
      case SyncState.pushing:
        _setState(SyncManagerState.syncing);
      case SyncState.synced:
        _setState(SyncManagerState.running);
        _retryAttempts = 0;
      case SyncState.error:
        if (_config.autoRetry && _retryAttempts < _config.maxRetryAttempts) {
          _scheduleRetry();
        } else {
          _setState(SyncManagerState.error);
        }
    }
  }

  /// Triggers a sync cycle (debounced).
  void _triggerSync() {
    if (_state == SyncManagerState.paused ||
        _state == SyncManagerState.stopped) {
      return;
    }

    if (_syncInProgress) {
      _log.fine('Sync already in progress, skipping trigger');
      return;
    }

    _performSync();
  }

  /// Performs the actual sync cycle.
  Future<SyncResult> _performSync() async {
    if (_syncInProgress) {
      return const SyncResult(state: SyncState.idle);
    }

    _syncInProgress = true;
    _log.info('Starting sync cycle');

    try {
      final result = await _syncEngine.sync();

      // Update stats
      _stats = _stats.copyWith(
        totalPushed: _stats.totalPushed + result.pushedCount,
        totalPulled: _stats.totalPulled + result.pulledCount,
        totalConflicts: _stats.totalConflicts + result.conflicts.length,
        syncCycles: _stats.syncCycles + 1,
        lastSyncTime: result.isSuccess ? DateTime.now() : _stats.lastSyncTime,
        pendingCount: _offlineQueue.length,
      );

      // Acknowledge synced operations
      if (result.isSuccess && result.pushedCount > 0) {
        await _offlineQueue.acknowledge(_syncEngine.localCursor);
        await _oplogService.acknowledge(_syncEngine.localCursor);
        _stats = _stats.copyWith(pendingCount: _offlineQueue.length);
      }

      // Emit result
      _syncResultController.add(result);

      if (result.isSuccess) {
        _log.info(
          'Sync completed: ${result.pulledCount} pulled, '
          '${result.pushedCount} pushed',
        );
      } else {
        _log.warning('Sync failed: ${result.error}');
        _stats = _stats.copyWith(failedAttempts: _stats.failedAttempts + 1);
      }

      return result;
    } finally {
      _syncInProgress = false;
    }
  }

  /// Gets pending operations for the sync engine.
  Future<List<SyncOperation>> _getPendingOperations(int sinceOpId) async {
    return _offlineQueue.getPending(
      sinceOpId: sinceOpId,
      limit: _config.maxBatchSize,
    );
  }

  /// Schedules a retry after failed sync.
  void _scheduleRetry() {
    _retryAttempts++;
    _log.info('Scheduling retry $_retryAttempts/${_config.maxRetryAttempts}');

    _retryTimer?.cancel();
    _retryTimer = Timer(_config.retryDelay, () {
      if (_state != SyncManagerState.stopped &&
          _state != SyncManagerState.paused) {
        _triggerSync();
      }
    });
  }

  /// Sets the state and notifies listeners.
  void _setState(SyncManagerState newState) {
    if (_state != newState) {
      _state = newState;
      _stateController.add(newState);
    }
  }

  /// Disposes resources.
  Future<void> dispose() async {
    await stop();
    await _stateController.close();
    await _syncResultController.close();
  }
}
