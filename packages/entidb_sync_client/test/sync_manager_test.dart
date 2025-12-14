/// SyncManager Tests
///
/// Tests for the integrated sync manager.
library;

import 'dart:async';

import 'package:entidb_sync_client/entidb_sync_client.dart';
import 'package:test/test.dart';

void main() {
  group('SyncManagerConfig', () {
    test('default configuration has sensible values', () {
      const config = SyncManagerConfig();

      expect(config.debounceDelay, const Duration(milliseconds: 500));
      expect(config.periodicSyncInterval, const Duration(minutes: 5));
      expect(config.maxBatchSize, 100);
      expect(config.syncOnStart, isTrue);
      expect(config.autoRetry, isTrue);
      expect(config.retryDelay, const Duration(seconds: 5));
      expect(config.maxRetryAttempts, 3);
    });

    test('realtime configuration minimizes latency', () {
      const config = SyncManagerConfig.realtime();

      expect(config.debounceDelay, const Duration(milliseconds: 100));
      expect(config.periodicSyncInterval, const Duration(minutes: 1));
      expect(config.maxBatchSize, 50);
    });

    test('battery saver configuration reduces frequency', () {
      const config = SyncManagerConfig.batterySaver();

      expect(config.debounceDelay, const Duration(seconds: 5));
      expect(config.periodicSyncInterval, const Duration(minutes: 15));
      expect(config.maxBatchSize, 200);
    });
  });

  group('SyncStats', () {
    test('default stats are zero', () {
      const stats = SyncStats();

      expect(stats.totalPushed, 0);
      expect(stats.totalPulled, 0);
      expect(stats.totalConflicts, 0);
      expect(stats.syncCycles, 0);
      expect(stats.failedAttempts, 0);
      expect(stats.lastSyncTime, isNull);
      expect(stats.pendingCount, 0);
    });

    test('copyWith creates new instance', () {
      const stats = SyncStats(totalPushed: 10);
      final updated = stats.copyWith(totalPulled: 5);

      expect(updated.totalPushed, 10);
      expect(updated.totalPulled, 5);
      expect(stats.totalPulled, 0); // Original unchanged
    });

    test('toString provides summary', () {
      const stats = SyncStats(totalPushed: 5, totalPulled: 3);
      expect(stats.toString(), contains('pushed: 5'));
      expect(stats.toString(), contains('pulled: 3'));
    });
  });

  group('SyncManagerState', () {
    test('has all expected states', () {
      expect(SyncManagerState.values, contains(SyncManagerState.stopped));
      expect(SyncManagerState.values, contains(SyncManagerState.running));
      expect(SyncManagerState.values, contains(SyncManagerState.syncing));
      expect(SyncManagerState.values, contains(SyncManagerState.paused));
      expect(SyncManagerState.values, contains(SyncManagerState.error));
    });
  });
}
