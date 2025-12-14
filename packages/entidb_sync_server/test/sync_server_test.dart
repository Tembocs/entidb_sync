import 'dart:typed_data';

import 'package:entidb_sync_protocol/entidb_sync_protocol.dart';
import 'package:entidb_sync_server/entidb_sync_server.dart';
import 'package:test/test.dart';

void main() {
  group('SyncService', () {
    late SyncService syncService;

    setUp(() {
      syncService = SyncService();
    });

    group('handleHandshake', () {
      test('returns server cursor and capabilities', () async {
        final request = HandshakeRequest(
          dbId: 'test-db',
          deviceId: 'device-1',
          clientInfo: ClientInfo(
            platform: 'test',
            appVersion: '1.0.0',
          ),
        );

        final response = await syncService.handleHandshake(request);

        expect(response.serverCursor, equals(0));
        expect(response.capabilities.pull, isTrue);
        expect(response.capabilities.push, isTrue);
        expect(response.capabilities.sse, isFalse);
      });
    });

    group('handlePush', () {
      test('accepts operations and returns acknowledgment', () async {
        final request = PushRequest(
          dbId: 'test-db',
          deviceId: 'device-1',
          ops: [
            SyncOperation(
              opId: 1,
              dbId: 'test-db',
              deviceId: 'device-1',
              collection: 'tasks',
              entityId: 'task-1',
              opType: OperationType.upsert,
              entityVersion: 1,
              entityCbor: Uint8List.fromList([0xa1, 0x61, 0x61, 0x01]),
              timestampMs: DateTime.now().millisecondsSinceEpoch,
            ),
          ],
        );

        final response = await syncService.handlePush(request);

        expect(response.acknowledgedUpToOpId, equals(1));
        expect(response.conflicts, isEmpty);
        expect(response.isFullyAccepted, isTrue);
        expect(syncService.oplogSize, equals(1));
      });

      test('detects conflicts for outdated entity versions', () async {
        // First push
        final firstPush = PushRequest(
          dbId: 'test-db',
          deviceId: 'device-1',
          ops: [
            SyncOperation(
              opId: 1,
              dbId: 'test-db',
              deviceId: 'device-1',
              collection: 'tasks',
              entityId: 'task-1',
              opType: OperationType.upsert,
              entityVersion: 1,
              entityCbor: Uint8List.fromList([0xa1]),
              timestampMs: DateTime.now().millisecondsSinceEpoch,
            ),
          ],
        );
        await syncService.handlePush(firstPush);

        // Conflicting push with same version
        final conflictingPush = PushRequest(
          dbId: 'test-db',
          deviceId: 'device-2',
          ops: [
            SyncOperation(
              opId: 1,
              dbId: 'test-db',
              deviceId: 'device-2',
              collection: 'tasks',
              entityId: 'task-1',
              opType: OperationType.upsert,
              entityVersion: 1, // Same version - conflict!
              entityCbor: Uint8List.fromList([0xa2]),
              timestampMs: DateTime.now().millisecondsSinceEpoch,
            ),
          ],
        );

        final response = await syncService.handlePush(conflictingPush);

        expect(response.conflicts.length, equals(1));
        expect(response.conflicts[0].entityId, equals('task-1'));
        expect(response.conflicts[0].serverState.entityVersion, equals(1));
        expect(response.isFullyAccepted, isFalse);
      });
    });

    group('handlePull', () {
      test('returns empty list when no operations', () async {
        final request = PullRequest(
          dbId: 'test-db',
          sinceCursor: 0,
          limit: 100,
        );

        final response = await syncService.handlePull(request);

        expect(response.ops, isEmpty);
        expect(response.nextCursor, equals(0));
        expect(response.hasMore, isFalse);
      });

      test('returns operations since cursor', () async {
        // Push some operations first
        await syncService.handlePush(PushRequest(
          dbId: 'test-db',
          deviceId: 'device-1',
          ops: [
            SyncOperation(
              opId: 1,
              dbId: 'test-db',
              deviceId: 'device-1',
              collection: 'tasks',
              entityId: 'task-1',
              opType: OperationType.upsert,
              entityVersion: 1,
              entityCbor: Uint8List.fromList([0xa1]),
              timestampMs: DateTime.now().millisecondsSinceEpoch,
            ),
            SyncOperation(
              opId: 2,
              dbId: 'test-db',
              deviceId: 'device-1',
              collection: 'notes',
              entityId: 'note-1',
              opType: OperationType.upsert,
              entityVersion: 1,
              entityCbor: Uint8List.fromList([0xa2]),
              timestampMs: DateTime.now().millisecondsSinceEpoch,
            ),
          ],
        ));

        // Pull all operations
        final response = await syncService.handlePull(PullRequest(
          dbId: 'test-db',
          sinceCursor: 0,
          limit: 100,
        ));

        expect(response.ops.length, equals(2));
        expect(response.nextCursor, equals(2));
        expect(response.hasMore, isFalse);
      });

      test('filters by collection', () async {
        // Push operations to different collections
        await syncService.handlePush(PushRequest(
          dbId: 'test-db',
          deviceId: 'device-1',
          ops: [
            SyncOperation(
              opId: 1,
              dbId: 'test-db',
              deviceId: 'device-1',
              collection: 'tasks',
              entityId: 'task-1',
              opType: OperationType.upsert,
              entityVersion: 1,
              entityCbor: Uint8List.fromList([0xa1]),
              timestampMs: DateTime.now().millisecondsSinceEpoch,
            ),
            SyncOperation(
              opId: 2,
              dbId: 'test-db',
              deviceId: 'device-1',
              collection: 'notes',
              entityId: 'note-1',
              opType: OperationType.upsert,
              entityVersion: 1,
              entityCbor: Uint8List.fromList([0xa2]),
              timestampMs: DateTime.now().millisecondsSinceEpoch,
            ),
          ],
        ));

        // Pull only tasks
        final response = await syncService.handlePull(PullRequest(
          dbId: 'test-db',
          sinceCursor: 0,
          limit: 100,
          collections: ['tasks'],
        ));

        expect(response.ops.length, equals(1));
        expect(response.ops[0].collection, equals('tasks'));
      });

      test('respects limit', () async {
        // Push multiple operations
        await syncService.handlePush(PushRequest(
          dbId: 'test-db',
          deviceId: 'device-1',
          ops: List.generate(
            5,
            (i) => SyncOperation(
              opId: i + 1,
              dbId: 'test-db',
              deviceId: 'device-1',
              collection: 'tasks',
              entityId: 'task-$i',
              opType: OperationType.upsert,
              entityVersion: 1,
              entityCbor: Uint8List.fromList([0xa1]),
              timestampMs: DateTime.now().millisecondsSinceEpoch,
            ),
          ),
        ));

        // Pull with limit
        final response = await syncService.handlePull(PullRequest(
          dbId: 'test-db',
          sinceCursor: 0,
          limit: 3,
        ));

        expect(response.ops.length, equals(3));
        expect(response.hasMore, isTrue);
        expect(response.nextCursor, equals(3));
      });
    });
  });

  group('ServerConfig', () {
    test('creates with defaults', () {
      final config = ServerConfig();

      expect(config.host, equals('0.0.0.0'));
      expect(config.port, equals(8080));
      expect(config.enableCors, isTrue);
    });
  });
}
