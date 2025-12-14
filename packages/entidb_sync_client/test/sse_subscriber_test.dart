/// SSE Subscriber Tests
import 'package:entidb_sync_client/entidb_sync_client.dart';
import 'package:test/test.dart';

void main() {
  group('SseSubscriberConfig', () {
    test('creates with required parameters', () {
      const config = SseSubscriberConfig(
        serverUrl: 'http://localhost:8080',
        deviceId: 'device-1',
      );

      expect(config.serverUrl, 'http://localhost:8080');
      expect(config.deviceId, 'device-1');
      expect(config.collections, isNull);
      expect(config.authToken, isNull);
      expect(config.autoReconnect, isTrue);
    });

    test('creates with all parameters', () {
      const config = SseSubscriberConfig(
        serverUrl: 'https://sync.example.com',
        deviceId: 'device-123',
        collections: ['users', 'posts'],
        authToken: 'jwt-token',
        autoReconnect: false,
        reconnectDelay: Duration(seconds: 5),
        maxReconnectAttempts: 3,
      );

      expect(config.serverUrl, 'https://sync.example.com');
      expect(config.deviceId, 'device-123');
      expect(config.collections, ['users', 'posts']);
      expect(config.authToken, 'jwt-token');
      expect(config.autoReconnect, isFalse);
      expect(config.reconnectDelay, const Duration(seconds: 5));
      expect(config.maxReconnectAttempts, 3);
    });
  });

  group('SseReceivedEvent', () {
    test('creates operations event', () {
      final event = SseReceivedEvent(
        type: SseEventType.operations,
        id: 'evt-1',
        data: {
          'cursor': 42,
          'operations': [
            {
              'opId': 1,
              'dbId': 'db1',
              'deviceId': 'device-1',
              'collection': 'users',
              'entityId': 'user-1',
              'opType': 'upsert',
              'entityVersion': 1,
              'timestampMs': 1234567890,
            },
          ],
          'count': 1,
        },
      );

      expect(event.type, SseEventType.operations);
      expect(event.id, 'evt-1');
      expect(event.cursor, 42);
      expect(event.operations, hasLength(1));
      expect(event.operations[0].collection, 'users');
    });

    test('creates connected event', () {
      const event = SseReceivedEvent(
        type: SseEventType.connected,
        data: {'subscriptionId': 'sub-123', 'cursor': 10},
      );

      expect(event.type, SseEventType.connected);
      expect(event.subscriptionId, 'sub-123');
      expect(event.cursor, 10);
    });

    test('creates error event', () {
      const event = SseReceivedEvent(
        type: SseEventType.error,
        data: {'message': 'Connection failed', 'code': 'CONN_ERR'},
      );

      expect(event.type, SseEventType.error);
      expect(event.errorMessage, 'Connection failed');
    });

    test('creates ping event', () {
      final event = SseReceivedEvent(
        type: SseEventType.ping,
        data: {'timestamp': DateTime.now().millisecondsSinceEpoch},
      );

      expect(event.type, SseEventType.ping);
      expect(event.operations, isEmpty);
    });
  });

  group('SseOperationInfo', () {
    test('creates from map', () {
      final info = SseOperationInfo.fromMap({
        'opId': 42,
        'dbId': 'db1',
        'deviceId': 'device-1',
        'collection': 'users',
        'entityId': 'user-123',
        'opType': 'upsert',
        'entityVersion': 5,
        'timestampMs': 1234567890,
      });

      expect(info.opId, 42);
      expect(info.dbId, 'db1');
      expect(info.deviceId, 'device-1');
      expect(info.collection, 'users');
      expect(info.entityId, 'user-123');
      expect(info.opType, OperationType.upsert);
      expect(info.entityVersion, 5);
      expect(info.timestampMs, 1234567890);
    });

    test('handles delete operation type', () {
      final info = SseOperationInfo.fromMap({
        'opId': 1,
        'dbId': 'db1',
        'deviceId': 'device-1',
        'collection': 'users',
        'entityId': 'user-1',
        'opType': 'delete',
        'entityVersion': 1,
        'timestampMs': 1234567890,
      });

      expect(info.opType, OperationType.delete);
    });

    test('defaults to upsert for unknown operation type', () {
      final info = SseOperationInfo.fromMap({
        'opId': 1,
        'dbId': 'db1',
        'deviceId': 'device-1',
        'collection': 'users',
        'entityId': 'user-1',
        'opType': 'unknown',
        'entityVersion': 1,
        'timestampMs': 1234567890,
      });

      expect(info.opType, OperationType.upsert);
    });
  });

  group('SseConnectionState', () {
    test('has expected values', () {
      expect(
        SseConnectionState.values,
        contains(SseConnectionState.disconnected),
      );
      expect(
        SseConnectionState.values,
        contains(SseConnectionState.connecting),
      );
      expect(SseConnectionState.values, contains(SseConnectionState.connected));
      expect(SseConnectionState.values, contains(SseConnectionState.error));
    });
  });

  group('SseSubscriber', () {
    test('starts in disconnected state', () {
      final subscriber = SseSubscriber(
        const SseSubscriberConfig(
          serverUrl: 'http://localhost:8080',
          deviceId: 'device-1',
        ),
      );

      expect(subscriber.state, SseConnectionState.disconnected);
      expect(subscriber.isConnected, isFalse);
      expect(subscriber.subscriptionId, isNull);

      subscriber.dispose();
    });

    test('throws when connecting after dispose', () async {
      final subscriber = SseSubscriber(
        const SseSubscriberConfig(
          serverUrl: 'http://localhost:8080',
          deviceId: 'device-1',
        ),
      );

      subscriber.dispose();

      expect(() => subscriber.connect(), throwsStateError);
    });

    test('provides event and state streams', () {
      final subscriber = SseSubscriber(
        const SseSubscriberConfig(
          serverUrl: 'http://localhost:8080',
          deviceId: 'device-1',
        ),
      );

      expect(subscriber.events, isA<Stream<SseReceivedEvent>>());
      expect(subscriber.stateChanges, isA<Stream<SseConnectionState>>());

      subscriber.dispose();
    });
  });
}
