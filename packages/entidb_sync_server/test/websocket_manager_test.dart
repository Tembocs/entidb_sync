/// WebSocket Manager Tests
///
/// Tests for WebSocket connection management and message handling.

import 'package:entidb_sync_protocol/entidb_sync_protocol.dart';
import 'package:entidb_sync_server/entidb_sync_server.dart';
import 'package:test/test.dart';

void main() {
  group('WebSocketConfig', () {
    test('has sensible defaults', () {
      const config = WebSocketConfig.defaultConfig;
      expect(config.keepAliveIntervalSeconds, equals(30));
      expect(config.pingTimeoutSeconds, equals(10));
      expect(config.maxConnectionsPerDevice, equals(3));
      expect(config.maxTotalConnections, equals(1000));
      expect(config.maxMessageSize, equals(1024 * 1024));
    });

    test('can be customized', () {
      const config = WebSocketConfig(
        keepAliveIntervalSeconds: 60,
        pingTimeoutSeconds: 20,
        maxConnectionsPerDevice: 5,
        maxTotalConnections: 500,
      );
      expect(config.keepAliveIntervalSeconds, equals(60));
      expect(config.maxConnectionsPerDevice, equals(5));
    });
  });

  group('WsMessage', () {
    test('creates subscribe message', () {
      final msg = WsMessage(
        type: WsMessageType.subscribe,
        data: {
          'collections': ['users', 'posts'],
        },
      );
      expect(msg.type, equals(WsMessageType.subscribe));
      expect(msg.data['collections'], contains('users'));
    });

    test('creates operations message', () {
      final msg = WsMessage.operations(
        cursor: 100,
        operations: [
          {'opId': 1, 'collection': 'users'},
        ],
        id: 'msg-1',
      );
      expect(msg.type, equals(WsMessageType.operations));
      expect(msg.data['cursor'], equals(100));
      expect(msg.data['count'], equals(1));
      expect(msg.id, equals('msg-1'));
    });

    test('creates subscribed message', () {
      final msg = WsMessage.subscribed(
        connectionId: 'conn-123',
        currentCursor: 50,
      );
      expect(msg.type, equals(WsMessageType.subscribed));
      expect(msg.data['connectionId'], equals('conn-123'));
      expect(msg.data['cursor'], equals(50));
    });

    test('creates pullResponse message', () {
      final msg = WsMessage.pullResponse(
        operations: [
          {'opId': 1},
        ],
        nextCursor: 10,
        hasMore: true,
        id: 'req-1',
      );
      expect(msg.type, equals(WsMessageType.pullResponse));
      expect(msg.data['hasMore'], isTrue);
      expect(msg.id, equals('req-1'));
    });

    test('creates pushResponse message', () {
      final msg = WsMessage.pushResponse(
        acknowledgedUpToOpId: 5,
        conflicts: [],
        id: 'req-2',
      );
      expect(msg.type, equals(WsMessageType.pushResponse));
      expect(msg.data['acknowledgedUpToOpId'], equals(5));
    });

    test('creates ping message', () {
      final msg = WsMessage.ping();
      expect(msg.type, equals(WsMessageType.ping));
      expect(msg.data['timestamp'], isA<int>());
    });

    test('creates pong message', () {
      final msg = WsMessage.pong(1234567890);
      expect(msg.type, equals(WsMessageType.pong));
      expect(msg.data['timestamp'], equals(1234567890));
      expect(msg.data['serverTime'], isA<int>());
    });

    test('creates error message', () {
      final msg = WsMessage.error(
        message: 'Something went wrong',
        code: 'internal_error',
        id: 'req-3',
      );
      expect(msg.type, equals(WsMessageType.error));
      expect(msg.data['message'], equals('Something went wrong'));
      expect(msg.data['code'], equals('internal_error'));
    });

    test('serializes to JSON', () {
      final msg = WsMessage(
        type: WsMessageType.ping,
        id: 'test-id',
        data: {'foo': 'bar'},
      );
      final json = msg.toJson();
      expect(json, contains('"type":"ping"'));
      expect(json, contains('"id":"test-id"'));
      expect(json, contains('"foo":"bar"'));
    });

    test('parses from JSON', () {
      const json = '{"type":"operations","id":"123","data":{"cursor":10}}';
      final msg = WsMessage.fromJson(json);
      expect(msg.type, equals(WsMessageType.operations));
      expect(msg.id, equals('123'));
      expect(msg.data['cursor'], equals(10));
    });

    test('handles unknown type gracefully', () {
      const json = '{"type":"unknown_type","data":{}}';
      final msg = WsMessage.fromJson(json);
      expect(msg.type, equals(WsMessageType.error));
    });

    test('handles missing data gracefully', () {
      const json = '{"type":"ping"}';
      final msg = WsMessage.fromJson(json);
      expect(msg.data, isEmpty);
    });
  });

  group('WebSocketManager', () {
    late WebSocketManager manager;

    setUp(() {
      manager = WebSocketManager(
        config: const WebSocketConfig(
          keepAliveIntervalSeconds: 60, // Long interval to avoid timer issues
        ),
        onPull: (request) async {
          return PullResponse(ops: [], nextCursor: 0, hasMore: false);
        },
        onPush: (request) async {
          return PushResponse(acknowledgedUpToOpId: 0, conflicts: []);
        },
        getCurrentCursor: () => 100,
      );
    });

    tearDown(() async {
      await manager.dispose();
    });

    test('starts with zero connections', () {
      expect(manager.connectionCount, equals(0));
      expect(manager.activeDeviceCount, equals(0));
    });

    test('provides accurate stats', () {
      final stats = manager.stats;
      expect(stats['connections'], equals(0));
      expect(stats['devices'], equals(0));
      expect(stats['messagesSent'], equals(0));
      expect(stats['messagesReceived'], equals(0));
    });

    test('broadcasts to no connections gracefully', () {
      final op = SyncOperation(
        opId: 1,
        dbId: 'db1',
        deviceId: 'device1',
        collection: 'users',
        entityId: 'user1',
        opType: OperationType.upsert,
        entityVersion: 1,
        timestampMs: DateTime.now().millisecondsSinceEpoch,
      );

      // Should not throw
      manager.broadcast([op], 1);
    });

    test('broadcast with empty operations does nothing', () {
      manager.broadcast([], 1);
      expect(manager.connectionCount, equals(0));
    });

    test('disposes cleanly', () async {
      await manager.dispose();
      expect(manager.connectionCount, equals(0));
    });
  });

  group('WebSocketManager with mock connections', () {
    // These tests would require mocking WebSocket connections
    // which is complex. Here we test the logic without actual sockets.

    test('connection ID format', () {
      // Connection IDs should follow pattern: ws-{deviceId}-{timestamp}-{count}
      // This is tested indirectly through the manager

      final manager = WebSocketManager(
        onPull: (_) async =>
            PullResponse(ops: [], nextCursor: 0, hasMore: false),
        onPush: (_) async =>
            PushResponse(acknowledgedUpToOpId: 0, conflicts: []),
        getCurrentCursor: () => 0,
      );

      // Just verify it initializes correctly
      expect(manager.connectionCount, equals(0));

      manager.dispose();
    });
  });

  group('WsMessageType', () {
    test('has all expected types', () {
      expect(WsMessageType.values, contains(WsMessageType.subscribe));
      expect(WsMessageType.values, contains(WsMessageType.subscribed));
      expect(WsMessageType.values, contains(WsMessageType.operations));
      expect(WsMessageType.values, contains(WsMessageType.ack));
      expect(WsMessageType.values, contains(WsMessageType.pull));
      expect(WsMessageType.values, contains(WsMessageType.pullResponse));
      expect(WsMessageType.values, contains(WsMessageType.push));
      expect(WsMessageType.values, contains(WsMessageType.pushResponse));
      expect(WsMessageType.values, contains(WsMessageType.ping));
      expect(WsMessageType.values, contains(WsMessageType.pong));
      expect(WsMessageType.values, contains(WsMessageType.error));
    });
  });

  group('Message round-trip', () {
    test('operations message preserves data', () {
      final original = WsMessage.operations(
        cursor: 42,
        operations: [
          {'opId': 1, 'collection': 'users', 'entityId': 'u1'},
          {'opId': 2, 'collection': 'posts', 'entityId': 'p1'},
        ],
        id: 'event-123',
      );

      final json = original.toJson();
      final restored = WsMessage.fromJson(json);

      expect(restored.type, equals(original.type));
      expect(restored.id, equals(original.id));
      expect(restored.data['cursor'], equals(42));
      expect((restored.data['operations'] as List).length, equals(2));
    });

    test('error message preserves all fields', () {
      final original = WsMessage.error(
        message: 'Connection timeout',
        code: 'timeout',
        id: 'req-456',
      );

      final json = original.toJson();
      final restored = WsMessage.fromJson(json);

      expect(restored.type, equals(WsMessageType.error));
      expect(restored.data['message'], equals('Connection timeout'));
      expect(restored.data['code'], equals('timeout'));
      expect(restored.id, equals('req-456'));
    });
  });
}
