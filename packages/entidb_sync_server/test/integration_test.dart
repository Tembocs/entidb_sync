/// Integration Tests
///
/// End-to-end tests for the sync protocol between client and server.
///
/// These tests verify:
/// - Complete sync cycles (handshake → pull → push)
/// - Conflict detection and resolution
/// - Offline queue behavior
/// - Multi-device synchronization
library;

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:entidb/entidb.dart' hide OperationType;
import 'package:entidb_sync_client/entidb_sync_client.dart';
import 'package:entidb_sync_server/entidb_sync_server.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:test/test.dart';

void main() {
  group('Client-Server Integration', () {
    late SyncService syncService;
    late HttpServer server;
    late Uri serverUrl;

    setUp(() async {
      // Create in-memory sync service
      syncService = SyncService();

      // Create router and handler
      final router = createSyncRouter(syncService);
      final handler = const Pipeline()
          .addMiddleware(createCorsMiddleware())
          .addHandler(router.call);

      // Start server on random port
      server = await shelf_io.serve(handler, 'localhost', 0);
      serverUrl = Uri.parse('http://localhost:${server.port}');
    });

    tearDown(() async {
      await server.close();
    });

    test('handshake establishes connection', () async {
      final config = TransportConfig(
        serverUrl: serverUrl,
        dbId: 'test-db',
        deviceId: 'test-device-1',
      );
      final transport = SyncHttpTransport(config: config);

      try {
        final response = await transport.handshake(
          const ClientInfo(platform: 'test', appVersion: '1.0.0'),
        );

        expect(response.serverCursor, isNotNull);
        expect(response.capabilities.pull, isTrue);
        expect(response.capabilities.push, isTrue);
      } finally {
        transport.close();
      }
    });

    test('pull retrieves operations from server', () async {
      // Push some operations to the server first
      final pushRequest = PushRequest(
        dbId: 'test-db',
        deviceId: 'device-1',
        ops: [
          SyncOperation(
            opId: 1,
            dbId: 'test-db',
            deviceId: 'device-1',
            collection: 'users',
            entityId: 'user-1',
            opType: OperationType.upsert,
            entityVersion: 1,
            entityCbor: Uint8List.fromList([
              0xa1,
              0x64,
              0x6e,
              0x61,
              0x6d,
              0x65,
              0x64,
              0x4a,
              0x6f,
              0x68,
              0x6e,
            ]),
            timestampMs: DateTime.now().millisecondsSinceEpoch,
          ),
        ],
      );
      await syncService.handlePush(pushRequest);

      // Create client and pull
      final config = TransportConfig(
        serverUrl: serverUrl,
        dbId: 'test-db',
        deviceId: 'test-device',
      );
      final transport = SyncHttpTransport(config: config);

      try {
        final response = await transport.pull(sinceCursor: 0, limit: 100);

        expect(response.ops, hasLength(1));
        expect(response.ops.first.collection, 'users');
        expect(response.ops.first.entityId, 'user-1');
        expect(response.hasMore, isFalse);
      } finally {
        transport.close();
      }
    });

    test('push sends operations to server', () async {
      final config = TransportConfig(
        serverUrl: serverUrl,
        dbId: 'test-db',
        deviceId: 'device-2',
      );
      final transport = SyncHttpTransport(config: config);

      try {
        final response = await transport.push([
          SyncOperation(
            opId: 1,
            dbId: 'test-db',
            deviceId: 'device-2',
            collection: 'products',
            entityId: 'product-1',
            opType: OperationType.upsert,
            entityVersion: 1,
            entityCbor: Uint8List.fromList([0xa1]),
            timestampMs: DateTime.now().millisecondsSinceEpoch,
          ),
        ]);

        expect(response.acknowledgedUpToOpId, 1);
        expect(response.conflicts, isEmpty);
      } finally {
        transport.close();
      }
    });

    test('full sync cycle with SyncEngine', () async {
      final config = TransportConfig(
        serverUrl: serverUrl,
        dbId: 'test-db',
        deviceId: 'sync-engine-device',
      );
      final transport = SyncHttpTransport(config: config);

      final engine = SyncEngine(
        transport: transport,
        clientInfo: const ClientInfo(platform: 'test', appVersion: '1.0.0'),
      );

      // Track pulled operations
      final pulledOps = <SyncOperation>[];
      engine.onApplyOperation = (op) async {
        pulledOps.add(op);
      };

      // Provide pending operations
      engine.onGetPendingOperations = (sinceOpId) async {
        return [
          SyncOperation(
            opId: sinceOpId + 1,
            dbId: 'test-db',
            deviceId: 'sync-engine-device',
            collection: 'tasks',
            entityId: 'task-1',
            opType: OperationType.upsert,
            entityVersion: 1,
            entityCbor: Uint8List.fromList([0xa0]),
            timestampMs: DateTime.now().millisecondsSinceEpoch,
          ),
        ];
      };

      // Track state changes
      final states = <SyncState>[];
      final stateSubscription = engine.stateStream.listen(states.add);

      // Perform sync
      final result = await engine.sync();

      // Allow stream events to propagate
      await Future<void>.delayed(const Duration(milliseconds: 10));

      expect(result.isSuccess, isTrue);
      expect(result.state, SyncState.synced);
      expect(result.pushedCount, 1);

      // Verify state transitions
      expect(states, contains(SyncState.connecting));
      expect(states, contains(SyncState.pulling));
      expect(states, contains(SyncState.pushing));
      expect(states, contains(SyncState.synced));

      await stateSubscription.cancel();
      engine.dispose();
    });
  });

  group('Conflict Detection', () {
    late SyncService syncService;

    setUp(() {
      syncService = SyncService();
    });

    test('detects version conflict on concurrent edits', () async {
      // Device 1 pushes an entity
      await syncService.handlePush(
        PushRequest(
          dbId: 'test-db',
          deviceId: 'device-1',
          ops: [
            SyncOperation(
              opId: 1,
              dbId: 'test-db',
              deviceId: 'device-1',
              collection: 'docs',
              entityId: 'doc-1',
              opType: OperationType.upsert,
              entityVersion: 1,
              entityCbor: Uint8List.fromList([0xa1, 0x61, 0x76, 0x01]),
              timestampMs: DateTime.now().millisecondsSinceEpoch,
            ),
          ],
        ),
      );

      // Device 2 tries to push same entity with same version (conflict!)
      final response = await syncService.handlePush(
        PushRequest(
          dbId: 'test-db',
          deviceId: 'device-2',
          ops: [
            SyncOperation(
              opId: 1,
              dbId: 'test-db',
              deviceId: 'device-2',
              collection: 'docs',
              entityId: 'doc-1',
              opType: OperationType.upsert,
              entityVersion: 1, // Same version as device 1
              entityCbor: Uint8List.fromList([0xa1, 0x61, 0x76, 0x02]),
              timestampMs: DateTime.now().millisecondsSinceEpoch,
            ),
          ],
        ),
      );

      expect(response.conflicts, hasLength(1));
      expect(response.conflicts.first.entityId, 'doc-1');
      expect(response.acknowledgedUpToOpId, 0);
    });

    test('no conflict when version is higher', () async {
      // Device 1 pushes an entity
      await syncService.handlePush(
        PushRequest(
          dbId: 'test-db',
          deviceId: 'device-1',
          ops: [
            SyncOperation(
              opId: 1,
              dbId: 'test-db',
              deviceId: 'device-1',
              collection: 'docs',
              entityId: 'doc-2',
              opType: OperationType.upsert,
              entityVersion: 1,
              entityCbor: Uint8List.fromList([0xa0]),
              timestampMs: DateTime.now().millisecondsSinceEpoch,
            ),
          ],
        ),
      );

      // Device 2 pushes same entity with higher version (no conflict)
      final response = await syncService.handlePush(
        PushRequest(
          dbId: 'test-db',
          deviceId: 'device-2',
          ops: [
            SyncOperation(
              opId: 1,
              dbId: 'test-db',
              deviceId: 'device-2',
              collection: 'docs',
              entityId: 'doc-2',
              opType: OperationType.upsert,
              entityVersion: 2, // Higher version
              entityCbor: Uint8List.fromList([0xa0]),
              timestampMs: DateTime.now().millisecondsSinceEpoch,
            ),
          ],
        ),
      );

      expect(response.conflicts, isEmpty);
      expect(response.acknowledgedUpToOpId, 1);
    });
  });

  group('OfflineQueue Integration', () {
    late Directory tempDir;
    late OfflineQueue queue;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('sync_queue_test_');
      queue = OfflineQueue(storagePath: tempDir.path);
      await queue.open();
    });

    tearDown(() async {
      await queue.close();
      await tempDir.delete(recursive: true);
    });

    test('queue persists across restarts', () async {
      // Enqueue operation
      await queue.enqueue(
        SyncOperation(
          opId: 1,
          dbId: 'test-db',
          deviceId: 'device-1',
          collection: 'notes',
          entityId: 'note-1',
          opType: OperationType.upsert,
          entityVersion: 1,
          entityCbor: Uint8List.fromList([0xa0]),
          timestampMs: DateTime.now().millisecondsSinceEpoch,
        ),
      );

      expect(queue.length, 1);

      // Close and reopen
      await queue.close();

      final queue2 = OfflineQueue(storagePath: tempDir.path);
      await queue2.open();

      expect(queue2.length, 1);
      final pending = await queue2.getPending();
      expect(pending.first.entityId, 'note-1');

      await queue2.close();
    });

    test('acknowledge removes operations', () async {
      await queue.enqueue(
        SyncOperation(
          opId: 1,
          dbId: 'test-db',
          deviceId: 'device-1',
          collection: 'notes',
          entityId: 'note-1',
          opType: OperationType.upsert,
          entityVersion: 1,
          timestampMs: DateTime.now().millisecondsSinceEpoch,
        ),
      );
      await queue.enqueue(
        SyncOperation(
          opId: 2,
          dbId: 'test-db',
          deviceId: 'device-1',
          collection: 'notes',
          entityId: 'note-2',
          opType: OperationType.upsert,
          entityVersion: 1,
          timestampMs: DateTime.now().millisecondsSinceEpoch,
        ),
      );

      expect(queue.length, 2);

      // Acknowledge first operation
      await queue.acknowledge(1);

      expect(queue.length, 1);
      final pending = await queue.getPending();
      expect(pending.first.opId, 2);
    });

    test('deduplicates operations with same opId', () async {
      final op = SyncOperation(
        opId: 1,
        dbId: 'test-db',
        deviceId: 'device-1',
        collection: 'notes',
        entityId: 'note-1',
        opType: OperationType.upsert,
        entityVersion: 1,
        timestampMs: DateTime.now().millisecondsSinceEpoch,
      );

      final added1 = await queue.enqueue(op);
      final added2 = await queue.enqueue(op);

      expect(added1, isTrue);
      expect(added2, isFalse);
      expect(queue.length, 1);
    });

    test('tracks retry count on failures', () async {
      await queue.enqueue(
        SyncOperation(
          opId: 1,
          dbId: 'test-db',
          deviceId: 'device-1',
          collection: 'notes',
          entityId: 'note-1',
          opType: OperationType.upsert,
          entityVersion: 1,
          timestampMs: DateTime.now().millisecondsSinceEpoch,
        ),
      );

      // Mark as failed multiple times
      await queue.markFailed(1, error: 'Network error');
      await queue.markFailed(1, error: 'Timeout');

      final stats = queue.getStats();
      expect(stats.retrying, 1);
      expect(stats.pending, 0);
    });
  });

  group('Multi-Device Sync', () {
    late SyncService syncService;
    late HttpServer server;
    late Uri serverUrl;

    setUp(() async {
      syncService = SyncService();
      final router = createSyncRouter(syncService);
      final handler = const Pipeline()
          .addMiddleware(createCorsMiddleware())
          .addHandler(router.call);
      server = await shelf_io.serve(handler, 'localhost', 0);
      serverUrl = Uri.parse('http://localhost:${server.port}');
    });

    tearDown(() async {
      await server.close();
    });

    test('device receives operations from other devices', () async {
      // Device 1 pushes data
      final config1 = TransportConfig(
        serverUrl: serverUrl,
        dbId: 'shared-db',
        deviceId: 'device-1',
      );
      final transport1 = SyncHttpTransport(config: config1);

      await transport1.handshake(
        const ClientInfo(platform: 'test', appVersion: '1.0.0'),
      );

      await transport1.push([
        SyncOperation(
          opId: 1,
          dbId: 'shared-db',
          deviceId: 'device-1',
          collection: 'shared',
          entityId: 'item-1',
          opType: OperationType.upsert,
          entityVersion: 1,
          entityCbor: Uint8List.fromList([0xa0]),
          timestampMs: DateTime.now().millisecondsSinceEpoch,
        ),
      ]);
      transport1.close();

      // Device 2 pulls and should see device 1's data
      final config2 = TransportConfig(
        serverUrl: serverUrl,
        dbId: 'shared-db',
        deviceId: 'device-2',
      );
      final transport2 = SyncHttpTransport(config: config2);

      await transport2.handshake(
        const ClientInfo(platform: 'test', appVersion: '1.0.0'),
      );

      final pullResponse = await transport2.pull(sinceCursor: 0, limit: 100);
      transport2.close();

      expect(pullResponse.ops, hasLength(1));
      expect(pullResponse.ops.first.deviceId, 'device-1');
      expect(pullResponse.ops.first.entityId, 'item-1');
    });

    test('cursor tracking enables incremental sync', () async {
      final config = TransportConfig(
        serverUrl: serverUrl,
        dbId: 'cursor-test',
        deviceId: 'cursor-device',
      );
      final transport = SyncHttpTransport(config: config);

      await transport.handshake(
        const ClientInfo(platform: 'test', appVersion: '1.0.0'),
      );

      // Push first batch
      await transport.push([
        SyncOperation(
          opId: 1,
          dbId: 'cursor-test',
          deviceId: 'cursor-device',
          collection: 'items',
          entityId: 'item-1',
          opType: OperationType.upsert,
          entityVersion: 1,
          entityCbor: Uint8List.fromList([0xa0]),
          timestampMs: DateTime.now().millisecondsSinceEpoch,
        ),
      ]);

      // Pull to get cursor
      final pull1 = await transport.pull(sinceCursor: 0, limit: 100);
      expect(pull1.ops, hasLength(1));
      final cursor1 = pull1.nextCursor;

      // Push second batch
      await transport.push([
        SyncOperation(
          opId: 2,
          dbId: 'cursor-test',
          deviceId: 'cursor-device',
          collection: 'items',
          entityId: 'item-2',
          opType: OperationType.upsert,
          entityVersion: 1,
          entityCbor: Uint8List.fromList([0xa0]),
          timestampMs: DateTime.now().millisecondsSinceEpoch,
        ),
      ]);

      // Pull with cursor should only get new items
      final pull2 = await transport.pull(sinceCursor: cursor1, limit: 100);
      expect(pull2.ops, hasLength(1));
      expect(pull2.ops.first.entityId, 'item-2');

      transport.close();
    });
  });

  group('EntiDB Persistence Integration', () {
    late EntiDB db;
    late EntiDBSyncService entidbSyncService;
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('entidb_sync_test_');
      db = await EntiDB.open(
        path: tempDir.path,
        config: EntiDBConfig.development(),
      );
      entidbSyncService = EntiDBSyncService(db: db);
      await entidbSyncService.initialize();
    });

    tearDown(() async {
      await db.close();
      await tempDir.delete(recursive: true);
    });

    test('persists operations across restarts', () async {
      // Push an operation
      await entidbSyncService.handleHandshake(
        const HandshakeRequest(
          dbId: 'persist-test',
          deviceId: 'persist-device',
          clientInfo: ClientInfo(platform: 'test', appVersion: '1.0.0'),
        ),
      );

      await entidbSyncService.handlePush(
        PushRequest(
          dbId: 'persist-test',
          deviceId: 'persist-device',
          ops: [
            SyncOperation(
              opId: 1,
              dbId: 'persist-test',
              deviceId: 'persist-device',
              collection: 'persistent',
              entityId: 'entity-1',
              opType: OperationType.upsert,
              entityVersion: 1,
              entityCbor: Uint8List.fromList([0xa0]),
              timestampMs: DateTime.now().millisecondsSinceEpoch,
            ),
          ],
        ),
      );

      final size1 = await entidbSyncService.oplogSize;
      expect(size1, 1);

      // Close and reopen
      await db.close();

      db = await EntiDB.open(
        path: tempDir.path,
        config: EntiDBConfig.development(),
      );
      final newService = EntiDBSyncService(db: db);
      await newService.initialize();

      // Check data persisted
      final pullResponse = await newService.handlePull(
        const PullRequest(dbId: 'persist-test', sinceCursor: 0, limit: 100),
      );
      expect(pullResponse.ops, hasLength(1));
      expect(pullResponse.ops.first.entityId, 'entity-1');
    });

    test('tracks device registrations', () async {
      await entidbSyncService.handleHandshake(
        const HandshakeRequest(
          dbId: 'device-test',
          deviceId: 'device-alpha',
          clientInfo: ClientInfo(platform: 'test', appVersion: '1.0.0'),
        ),
      );

      await entidbSyncService.handleHandshake(
        const HandshakeRequest(
          dbId: 'device-test',
          deviceId: 'device-beta',
          clientInfo: ClientInfo(platform: 'test', appVersion: '1.0.0'),
        ),
      );

      final stats = await entidbSyncService.getStats();
      expect(stats['deviceCount'], 2);
    });
  });
}
