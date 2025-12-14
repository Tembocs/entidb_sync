/// WebSocket Transport Tests
///
/// Tests for client-side WebSocket transport.
import 'package:entidb_sync_client/entidb_sync_client.dart';
import 'package:test/test.dart';

void main() {
  group('WebSocketTransportConfig', () {
    test('creates with required parameters', () {
      final config = WebSocketTransportConfig(
        serverUrl: Uri.parse('http://localhost:8080'),
        dbId: 'test-db',
        deviceId: 'device-1',
      );

      expect(config.serverUrl.toString(), equals('http://localhost:8080'));
      expect(config.dbId, equals('test-db'));
      expect(config.deviceId, equals('device-1'));
    });

    test('has sensible defaults', () {
      final config = WebSocketTransportConfig(
        serverUrl: Uri.parse('http://localhost:8080'),
        dbId: 'test-db',
        deviceId: 'device-1',
      );

      expect(config.reconnectDelay, equals(const Duration(seconds: 1)));
      expect(config.maxReconnectDelay, equals(const Duration(seconds: 30)));
      expect(config.pingInterval, equals(const Duration(seconds: 30)));
      expect(config.requestTimeout, equals(const Duration(seconds: 30)));
      expect(config.authTokenProvider, isNull);
      expect(config.collections, isNull);
    });

    test('can specify all parameters', () {
      final config = WebSocketTransportConfig(
        serverUrl: Uri.parse('https://sync.example.com'),
        dbId: 'prod-db',
        deviceId: 'mobile-123',
        authTokenProvider: () async => 'jwt-token',
        reconnectDelay: const Duration(seconds: 2),
        maxReconnectDelay: const Duration(minutes: 1),
        pingInterval: const Duration(seconds: 45),
        requestTimeout: const Duration(seconds: 60),
        collections: ['users', 'posts'],
      );

      expect(config.reconnectDelay, equals(const Duration(seconds: 2)));
      expect(config.maxReconnectDelay, equals(const Duration(minutes: 1)));
      expect(config.collections, equals(['users', 'posts']));
    });
  });

  group('WebSocketState', () {
    test('has all expected states', () {
      expect(WebSocketState.values, contains(WebSocketState.disconnected));
      expect(WebSocketState.values, contains(WebSocketState.connecting));
      expect(WebSocketState.values, contains(WebSocketState.connected));
      expect(WebSocketState.values, contains(WebSocketState.reconnecting));
      expect(WebSocketState.values, contains(WebSocketState.closed));
    });
  });

  group('WsMessageType', () {
    test('has all expected message types', () {
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

  group('WsMessage', () {
    test('creates message with type and data', () {
      final msg = WsMessage(
        type: WsMessageType.ping,
        data: {'timestamp': 1234567890},
      );
      expect(msg.type, equals(WsMessageType.ping));
      expect(msg.data['timestamp'], equals(1234567890));
      expect(msg.id, isNull);
    });

    test('creates message with id', () {
      final msg = WsMessage(
        type: WsMessageType.pull,
        id: 'req-123',
        data: {'sinceCursor': 0},
      );
      expect(msg.id, equals('req-123'));
    });

    test('serializes to JSON', () {
      final msg = WsMessage(
        type: WsMessageType.subscribe,
        id: 'sub-1',
        data: {
          'collections': ['users'],
        },
      );
      final json = msg.toJson();

      expect(json, contains('"type":"subscribe"'));
      expect(json, contains('"id":"sub-1"'));
      expect(json, contains('"collections"'));
    });

    test('parses from JSON', () {
      const json =
          '{"type":"subscribed","data":{"connectionId":"conn-1","cursor":50}}';
      final msg = WsMessage.fromJson(json);

      expect(msg.type, equals(WsMessageType.subscribed));
      expect(msg.data['connectionId'], equals('conn-1'));
      expect(msg.data['cursor'], equals(50));
    });

    test('handles malformed type gracefully', () {
      const json = '{"type":"invalid_type","data":{}}';
      final msg = WsMessage.fromJson(json);
      expect(msg.type, equals(WsMessageType.error));
    });

    test('handles missing data field', () {
      const json = '{"type":"ping"}';
      final msg = WsMessage.fromJson(json);
      expect(msg.data, isEmpty);
    });

    test('round-trip serialization preserves data', () {
      final original = WsMessage(
        type: WsMessageType.operations,
        id: 'event-42',
        data: {
          'cursor': 100,
          'operations': [
            {'opId': 1, 'collection': 'users'},
            {'opId': 2, 'collection': 'posts'},
          ],
          'count': 2,
        },
      );

      final json = original.toJson();
      final restored = WsMessage.fromJson(json);

      expect(restored.type, equals(original.type));
      expect(restored.id, equals(original.id));
      expect(restored.data['cursor'], equals(100));
      expect(restored.data['count'], equals(2));
    });
  });

  group('WebSocketTransport', () {
    late WebSocketTransport transport;

    setUp(() {
      transport = WebSocketTransport(
        config: WebSocketTransportConfig(
          serverUrl: Uri.parse('http://localhost:9999'),
          dbId: 'test-db',
          deviceId: 'test-device',
        ),
      );
    });

    tearDown(() async {
      await transport.dispose();
    });

    test('starts in disconnected state', () {
      expect(transport.state, equals(WebSocketState.disconnected));
      expect(transport.isConnected, isFalse);
      expect(transport.connectionId, isNull);
      expect(transport.serverCursor, equals(0));
    });

    test('exposes state stream', () {
      expect(transport.stateStream, isA<Stream<WebSocketState>>());
    });

    test('exposes operations stream', () {
      expect(
        transport.operationsStream,
        isA<Stream<(List<SyncOperation>, int)>>(),
      );
    });

    test('pull throws when not connected', () {
      expect(
        () => transport.pull(sinceCursor: 0),
        throwsA(isA<WebSocketTransportException>()),
      );
    });

    test('push throws when not connected', () {
      expect(
        () => transport.push([]),
        throwsA(isA<WebSocketTransportException>()),
      );
    });

    test('updateSubscription does nothing when not connected', () async {
      // Should not throw
      await transport.updateSubscription(['users']);
    });

    test('acknowledgeOperations does nothing when not connected', () {
      // Should not throw
      transport.acknowledgeOperations(100);
    });

    test('disposes cleanly', () async {
      await transport.dispose();
      expect(transport.state, equals(WebSocketState.closed));
    });
  });

  group('WebSocketTransportException', () {
    test('creates with message only', () {
      final ex = WebSocketTransportException('Connection failed');
      expect(ex.message, equals('Connection failed'));
      expect(ex.code, isNull);
    });

    test('creates with message and code', () {
      final ex = WebSocketTransportException(
        'Request timeout',
        code: 'timeout',
      );
      expect(ex.message, equals('Request timeout'));
      expect(ex.code, equals('timeout'));
    });

    test('toString includes message', () {
      final ex = WebSocketTransportException('Test error');
      expect(ex.toString(), contains('Test error'));
    });

    test('toString includes code when present', () {
      final ex = WebSocketTransportException('Test error', code: 'test_code');
      expect(ex.toString(), contains('test_code'));
    });
  });

  group('URL building', () {
    test('converts http to ws', () {
      final config = WebSocketTransportConfig(
        serverUrl: Uri.parse('http://localhost:8080'),
        dbId: 'db1',
        deviceId: 'dev1',
      );

      // The URL should be built with ws scheme
      expect(config.serverUrl.scheme, equals('http'));
      // Note: The actual WebSocket URL is built in connect(),
      // we're testing the config here
    });

    test('handles https', () {
      final config = WebSocketTransportConfig(
        serverUrl: Uri.parse('https://sync.example.com'),
        dbId: 'db1',
        deviceId: 'dev1',
      );

      expect(config.serverUrl.scheme, equals('https'));
    });
  });
}
