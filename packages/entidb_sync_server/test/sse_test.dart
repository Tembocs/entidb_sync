/// SSE Manager Tests
///
/// Tests for the Server-Sent Events manager.
import 'dart:typed_data';

import 'package:entidb_sync_server/entidb_sync_server.dart';
import 'package:test/test.dart';

void main() {
  group('SseConfig', () {
    test('has sensible defaults', () {
      const config = SseConfig.defaultConfig;

      expect(config.keepAliveIntervalSeconds, 30);
      expect(config.maxConnectionsPerDevice, 3);
      expect(config.maxTotalConnections, 1000);
    });

    test('can be customized', () {
      const config = SseConfig(
        keepAliveIntervalSeconds: 60,
        maxConnectionsPerDevice: 5,
        maxTotalConnections: 500,
      );

      expect(config.keepAliveIntervalSeconds, 60);
      expect(config.maxConnectionsPerDevice, 5);
      expect(config.maxTotalConnections, 500);
    });
  });

  group('SseEvent', () {
    test('creates operations event', () {
      final event = SseEvent.operations(
        cursor: 42,
        operations: [
          {'opId': 1, 'collection': 'users'},
        ],
        id: 'evt-1',
      );

      expect(event.type, SseEventType.operations);
      expect(event.id, 'evt-1');
      expect(event.data['cursor'], 42);
      expect(event.data['count'], 1);
    });

    test('creates ping event', () {
      final event = SseEvent.ping();

      expect(event.type, SseEventType.ping);
      expect(event.data['timestamp'], isA<int>());
    });

    test('creates connected event', () {
      final event = SseEvent.connected(
        subscriptionId: 'sub-123',
        currentCursor: 10,
      );

      expect(event.type, SseEventType.connected);
      expect(event.data['subscriptionId'], 'sub-123');
      expect(event.data['cursor'], 10);
    });

    test('creates error event', () {
      final event = SseEvent.error(
        message: 'Connection failed',
        code: 'CONN_ERR',
      );

      expect(event.type, SseEventType.error);
      expect(event.data['message'], 'Connection failed');
      expect(event.data['code'], 'CONN_ERR');
    });

    test('converts to SSE format string', () {
      final event = SseEvent.connected(
        subscriptionId: 'test',
        currentCursor: 0,
      );

      final sseString = event.toSseString();

      expect(sseString, contains('event: connected'));
      expect(sseString, contains('data: '));
      expect(sseString, contains('subscriptionId'));
    });
  });

  group('SseManager', () {
    late SseManager manager;

    setUp(() {
      manager = SseManager(
        config: const SseConfig(
          keepAliveIntervalSeconds: 300, // Long timeout for tests
          maxConnectionsPerDevice: 3,
          maxTotalConnections: 10,
        ),
      );
    });

    tearDown(() {
      manager.dispose();
    });

    test('subscribes a device', () {
      final subscription = manager.subscribe(deviceId: 'device-1');

      expect(subscription, isNotNull);
      expect(subscription!.deviceId, 'device-1');
      expect(subscription.isActive, isTrue);
      expect(manager.subscriptionCount, 1);
      expect(manager.activeDeviceCount, 1);
    });

    test('subscribes with collection filter', () {
      final subscription = manager.subscribe(
        deviceId: 'device-1',
        collections: ['users', 'posts'],
      );

      expect(subscription, isNotNull);
      expect(subscription!.collections, ['users', 'posts']);
    });

    test('unsubscribes a device', () {
      final subscription = manager.subscribe(deviceId: 'device-1');

      manager.unsubscribe(subscription!.subscriptionId);

      expect(subscription.isActive, isFalse);
      expect(manager.subscriptionCount, 0);
      expect(manager.activeDeviceCount, 0);
    });

    test('limits connections per device', () {
      // Subscribe 3 times (max per device)
      final sub1 = manager.subscribe(deviceId: 'device-1');
      final sub2 = manager.subscribe(deviceId: 'device-1');
      final sub3 = manager.subscribe(deviceId: 'device-1');

      expect(sub1, isNotNull);
      expect(sub2, isNotNull);
      expect(sub3, isNotNull);
      expect(manager.subscriptionCount, 3);

      // 4th subscription should close oldest and succeed
      final sub4 = manager.subscribe(deviceId: 'device-1');

      expect(sub4, isNotNull);
      // After closing oldest and adding new, count is still 3
      expect(sub1!.isActive, isFalse); // Oldest was closed
      expect(sub4!.isActive, isTrue); // New one is active
    });

    test('limits total connections', () {
      // Create 10 devices (max total)
      for (var i = 0; i < 10; i++) {
        final sub = manager.subscribe(deviceId: 'device-$i');
        expect(sub, isNotNull);
      }

      expect(manager.subscriptionCount, 10);

      // 11th device should fail
      final sub = manager.subscribe(deviceId: 'device-overflow');
      expect(sub, isNull);
    });

    test('broadcasts operations to all subscribers', () async {
      final sub1 = manager.subscribe(deviceId: 'device-1');
      final sub2 = manager.subscribe(deviceId: 'device-2');

      final events1 = <String>[];
      final events2 = <String>[];

      sub1!.stream.listen(events1.add);
      sub2!.stream.listen(events2.add);

      // Broadcast an operation
      final ops = [
        SyncOperation(
          opId: 1,
          dbId: 'db1',
          deviceId: 'device-1',
          collection: 'users',
          entityId: 'user-1',
          opType: OperationType.upsert,
          entityVersion: 1,
          entityCbor: Uint8List.fromList([1, 2, 3]),
          timestampMs: DateTime.now().millisecondsSinceEpoch,
        ),
      ];

      manager.broadcast(ops, 1);

      // Allow async delivery
      await Future<void>.delayed(const Duration(milliseconds: 10));

      expect(events1, hasLength(1));
      expect(events2, hasLength(1));
      expect(events1[0], contains('operations'));
    });

    test('filters broadcasts by collection', () async {
      final subAll = manager.subscribe(deviceId: 'device-1');
      final subUsers = manager.subscribe(
        deviceId: 'device-2',
        collections: ['users'],
      );
      final subPosts = manager.subscribe(
        deviceId: 'device-3',
        collections: ['posts'],
      );

      final eventsAll = <String>[];
      final eventsUsers = <String>[];
      final eventsPosts = <String>[];

      subAll!.stream.listen(eventsAll.add);
      subUsers!.stream.listen(eventsUsers.add);
      subPosts!.stream.listen(eventsPosts.add);

      // Broadcast a users operation
      final ops = [
        SyncOperation(
          opId: 1,
          dbId: 'db1',
          deviceId: 'device-1',
          collection: 'users',
          entityId: 'user-1',
          opType: OperationType.upsert,
          entityVersion: 1,
          entityCbor: Uint8List.fromList([1, 2, 3]),
          timestampMs: DateTime.now().millisecondsSinceEpoch,
        ),
      ];

      manager.broadcast(ops, 1);

      await Future<void>.delayed(const Duration(milliseconds: 10));

      expect(eventsAll, hasLength(1)); // Gets all
      expect(eventsUsers, hasLength(1)); // Gets users
      expect(eventsPosts, hasLength(0)); // Filtered out
    });

    test('sends connected event', () async {
      final sub = manager.subscribe(deviceId: 'device-1');

      final events = <String>[];
      sub!.stream.listen(events.add);

      manager.sendConnectedEvent(sub, 42);

      await Future<void>.delayed(const Duration(milliseconds: 10));

      expect(events, hasLength(1));
      expect(events[0], contains('connected'));
      expect(events[0], contains('42'));
    });

    test('tracks stats', () async {
      manager.subscribe(deviceId: 'device-1');
      manager.subscribe(deviceId: 'device-2');

      final stats = manager.stats;

      expect(stats['subscriptions'], 2);
      expect(stats['devices'], 2);
      expect(stats['eventsSent'], 0);
    });
  });

  group('SyncService SSE integration', () {
    test('reports SSE capability when manager is set', () async {
      final syncService = SyncService();
      final sseManager = SseManager();

      syncService.setSseManager(sseManager);

      final response = await syncService.handleHandshake(
        HandshakeRequest(
          dbId: 'db1',
          deviceId: 'device-1',
          clientInfo: const ClientInfo(platform: 'test', appVersion: '1.0.0'),
        ),
      );

      expect(response.capabilities.sse, isTrue);

      sseManager.dispose();
    });

    test('broadcasts on push', () async {
      final syncService = SyncService();
      final sseManager = SseManager();

      syncService.setSseManager(sseManager);

      // Create a subscription
      final sub = sseManager.subscribe(deviceId: 'device-2');
      final events = <String>[];
      sub!.stream.listen(events.add);

      // Push from another device
      await syncService.handlePush(
        PushRequest(
          dbId: 'db1',
          deviceId: 'device-1',
          ops: [
            SyncOperation(
              opId: 1,
              dbId: 'db1',
              deviceId: 'device-1',
              collection: 'users',
              entityId: 'user-1',
              opType: OperationType.upsert,
              entityVersion: 1,
              entityCbor: Uint8List.fromList([1, 2, 3]),
              timestampMs: DateTime.now().millisecondsSinceEpoch,
            ),
          ],
        ),
      );

      await Future<void>.delayed(const Duration(milliseconds: 10));

      expect(events, hasLength(1));
      expect(events[0], contains('operations'));

      sseManager.dispose();
    });
  });
}
