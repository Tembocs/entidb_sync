import 'dart:typed_data';

import 'package:entidb_sync_client/entidb_sync_client.dart';
import 'package:test/test.dart';

void main() {
  group('ConflictResolvers', () {
    final testConflict = Conflict(
      collection: 'tasks',
      entityId: 'task-1',
      clientOp: SyncOperation(
        opId: 1,
        dbId: 'test-db',
        deviceId: 'device-1',
        collection: 'tasks',
        entityId: 'task-1',
        opType: OperationType.upsert,
        entityVersion: 1,
        entityCbor: Uint8List.fromList([0xa1]),
        timestampMs: 1000,
      ),
      serverState: ServerState(
        entityVersion: 2,
        entityCbor: Uint8List.fromList([0xa2]),
        lastModified: DateTime.fromMillisecondsSinceEpoch(2000),
      ),
    );

    test('ServerWinsResolver returns null', () async {
      const resolver = ServerWinsResolver();
      final result = await resolver.resolve(testConflict);
      expect(result, isNull);
    });

    test('ClientWinsResolver returns operation with incremented version',
        () async {
      const resolver = ClientWinsResolver();
      final result = await resolver.resolve(testConflict);

      expect(result, isNotNull);
      expect(result!.entityVersion, equals(3)); // server version + 1
      expect(result.entityCbor, equals(testConflict.clientOp.entityCbor));
    });

    test('LastWriteWinsResolver respects timestamps', () async {
      const resolver = LastWriteWinsResolver();

      // Client is older - server wins
      final result1 = await resolver.resolve(testConflict);
      expect(result1, isNull);

      // Client is newer - client wins
      final newerClientConflict = Conflict(
        collection: 'tasks',
        entityId: 'task-1',
        clientOp: SyncOperation(
          opId: 1,
          dbId: 'test-db',
          deviceId: 'device-1',
          collection: 'tasks',
          entityId: 'task-1',
          opType: OperationType.upsert,
          entityVersion: 1,
          entityCbor: Uint8List.fromList([0xa1]),
          timestampMs: 3000, // Newer than server
        ),
        serverState: ServerState(
          entityVersion: 2,
          entityCbor: Uint8List.fromList([0xa2]),
          lastModified: DateTime.fromMillisecondsSinceEpoch(2000),
        ),
      );

      final result2 = await resolver.resolve(newerClientConflict);
      expect(result2, isNotNull);
      expect(result2!.entityVersion, equals(3));
    });

    test('CustomResolver uses provided callback', () async {
      var called = false;
      final resolver = CustomResolver((conflict) async {
        called = true;
        return null;
      });

      await resolver.resolve(testConflict);
      expect(called, isTrue);
    });
  });

  group('TransportConfig', () {
    test('creates with required parameters', () {
      final config = TransportConfig(
        serverUrl: Uri.parse('https://sync.example.com'),
        dbId: 'test-db',
        deviceId: 'device-1',
      );

      expect(config.serverUrl.host, equals('sync.example.com'));
      expect(config.dbId, equals('test-db'));
      expect(config.timeout.inSeconds, equals(30)); // default
      expect(config.maxRetries, equals(3)); // default
    });
  });

  group('SyncResult', () {
    test('isSuccess returns true for synced state', () {
      const result = SyncResult(state: SyncState.synced);
      expect(result.isSuccess, isTrue);
    });

    test('isSuccess returns false for error state', () {
      const result = SyncResult(state: SyncState.error, error: 'test error');
      expect(result.isSuccess, isFalse);
    });

    test('hasConflicts returns true when conflicts exist', () {
      final result = SyncResult(
        state: SyncState.synced,
        conflicts: [
          Conflict(
            collection: 'tasks',
            entityId: 'task-1',
            clientOp: SyncOperation(
              opId: 1,
              dbId: 'db',
              deviceId: 'd',
              collection: 'tasks',
              entityId: 'task-1',
              opType: OperationType.upsert,
              entityVersion: 1,
              timestampMs: 0,
            ),
            serverState: ServerState(
              entityVersion: 2,
              entityCbor: Uint8List(0),
            ),
          ),
        ],
      );
      expect(result.hasConflicts, isTrue);
    });
  });

  group('OplogConfig', () {
    test('creates with required parameters', () {
      const config = OplogConfig(
        walPath: '/path/to/wal',
        dbId: 'test-db',
        deviceId: 'device-1',
      );

      expect(config.walPath, equals('/path/to/wal'));
      expect(config.persistState, isTrue); // default
      expect(config.maxBufferSize, equals(1000)); // default
    });
  });

  group('OplogState', () {
    test('serializes to/from JSON', () {
      final state = OplogState(
        lastLsn: 100,
        lastOpId: 50,
        lastProcessedAt: DateTime(2024, 1, 15),
      );

      final json = state.toJson();
      final restored = OplogState.fromJson(json);

      expect(restored.lastLsn, equals(100));
      expect(restored.lastOpId, equals(50));
      expect(restored.lastProcessedAt, equals(DateTime(2024, 1, 15)));
    });
  });
}
