import 'dart:typed_data';

import 'package:entidb_sync_protocol/entidb_sync_protocol.dart';
import 'package:test/test.dart';

void main() {
  group('SyncOperation', () {
    test('serializes and deserializes correctly', () {
      final op = SyncOperation(
        opId: 1,
        dbId: 'test-db',
        deviceId: 'device-001',
        collection: 'users',
        entityId: 'user-123',
        opType: OperationType.upsert,
        entityVersion: 2,
        entityCbor: Uint8List.fromList([0xa1, 0x61, 0x61, 0x01]),
        timestampMs: 1234567890,
      );

      final bytes = op.toBytes();
      final deserialized = SyncOperation.fromBytes(bytes);

      expect(deserialized.opId, equals(op.opId));
      expect(deserialized.dbId, equals(op.dbId));
      expect(deserialized.deviceId, equals(op.deviceId));
      expect(deserialized.collection, equals(op.collection));
      expect(deserialized.entityId, equals(op.entityId));
      expect(deserialized.opType, equals(op.opType));
      expect(deserialized.entityVersion, equals(op.entityVersion));
      expect(deserialized.entityCbor, equals(op.entityCbor));
      expect(deserialized.timestampMs, equals(op.timestampMs));
    });

    test('equality works correctly', () {
      final op1 = SyncOperation(
        opId: 1,
        dbId: 'test-db',
        deviceId: 'device-001',
        collection: 'users',
        entityId: 'user-123',
        opType: OperationType.upsert,
        entityVersion: 2,
        entityCbor: Uint8List.fromList([0xa1, 0x61, 0x61, 0x01]),
        timestampMs: 1234567890,
      );

      final op2 = SyncOperation(
        opId: 1,
        dbId: 'test-db',
        deviceId: 'device-001',
        collection: 'users',
        entityId: 'user-123',
        opType: OperationType.upsert,
        entityVersion: 2,
        entityCbor: Uint8List.fromList([0xa1, 0x61, 0x61, 0x01]),
        timestampMs: 1234567890,
      );

      expect(op1, equals(op2));
      expect(op1.hashCode, equals(op2.hashCode));
    });
  });

  group('SyncCursor', () {
    test('creates initial cursor correctly', () {
      final cursor = SyncCursor.initial();
      expect(cursor.lastOpId, equals(0));
      expect(cursor.serverCursor, equals(0));
      expect(cursor.lastSyncAt.millisecondsSinceEpoch, equals(0));
    });

    test('serializes to/from JSON', () {
      final cursor = SyncCursor(
        lastOpId: 42,
        serverCursor: 100,
        lastSyncAt: DateTime(2024, 1, 15, 10, 30),
      );

      final json = cursor.toJson();
      final deserialized = SyncCursor.fromJson(json);

      expect(deserialized.lastOpId, equals(cursor.lastOpId));
      expect(deserialized.serverCursor, equals(cursor.serverCursor));
      expect(deserialized.lastSyncAt, equals(cursor.lastSyncAt));
    });

    test('copyWith creates modified copy', () {
      final original = SyncCursor.initial();
      final updated = original.copyWith(lastOpId: 10, serverCursor: 20);

      expect(updated.lastOpId, equals(10));
      expect(updated.serverCursor, equals(20));
      expect(updated.lastSyncAt, equals(original.lastSyncAt));
    });
  });

  group('ProtocolVersion', () {
    test('v1 is compatible with itself', () {
      expect(ProtocolVersion.v1.isCompatible(1), isTrue);
    });

    test('version 0 is not compatible', () {
      expect(ProtocolVersion.v1.isCompatible(0), isFalse);
    });
  });

  group('CBOR Encoders/Decoders', () {
    test('round-trips simple map', () {
      final original = {
        'string': 'hello',
        'int': 42,
        'bool': true,
        'null': null,
      };

      final bytes = encodeToCbor(original);
      final decoded = decodeFromCbor(bytes);

      expect(decoded['string'], equals('hello'));
      expect(decoded['int'], equals(42));
      expect(decoded['bool'], equals(true));
      expect(decoded['null'], isNull);
    });

    test('round-trips nested structures', () {
      final original = {
        'nested': {
          'inner': 'value',
          'number': 123,
        },
        'list': [1, 2, 3],
      };

      final bytes = encodeToCbor(original);
      final decoded = decodeFromCbor(bytes);

      expect((decoded['nested'] as Map)['inner'], equals('value'));
      expect((decoded['nested'] as Map)['number'], equals(123));
      expect(decoded['list'], equals([1, 2, 3]));
    });

    test('handles Uint8List', () {
      final original = {
        'bytes': Uint8List.fromList([0xa1, 0x61, 0x61, 0x01]),
      };

      final bytes = encodeToCbor(original);
      final decoded = decodeFromCbor(bytes);

      expect(decoded['bytes'],
          equals(Uint8List.fromList([0xa1, 0x61, 0x61, 0x01])));
    });
  });

  group('HandshakeRequest', () {
    test('serializes and deserializes correctly', () {
      final request = HandshakeRequest(
        dbId: 'production-db',
        deviceId: 'android-a92f1',
        clientInfo: ClientInfo(
          platform: 'android',
          appVersion: '1.2.3',
        ),
      );

      final bytes = request.toBytes();
      final deserialized = HandshakeRequest.fromBytes(bytes);

      expect(deserialized.dbId, equals('production-db'));
      expect(deserialized.deviceId, equals('android-a92f1'));
      expect(deserialized.clientInfo.platform, equals('android'));
      expect(deserialized.clientInfo.appVersion, equals('1.2.3'));
    });
  });

  group('HandshakeResponse', () {
    test('serializes and deserializes correctly', () {
      final response = HandshakeResponse(
        serverCursor: 12345,
        capabilities: ServerCapabilities(
          pull: true,
          push: true,
          sse: false,
        ),
        sessionToken: 'token-abc',
      );

      final bytes = response.toBytes();
      final deserialized = HandshakeResponse.fromBytes(bytes);

      expect(deserialized.serverCursor, equals(12345));
      expect(deserialized.capabilities.pull, isTrue);
      expect(deserialized.capabilities.push, isTrue);
      expect(deserialized.capabilities.sse, isFalse);
      expect(deserialized.sessionToken, equals('token-abc'));
    });
  });

  group('PullRequest', () {
    test('serializes and deserializes correctly', () {
      final request = PullRequest(
        dbId: 'production-db',
        sinceCursor: 12000,
        limit: 50,
        collections: ['tasks', 'notes'],
      );

      final bytes = request.toBytes();
      final deserialized = PullRequest.fromBytes(bytes);

      expect(deserialized.dbId, equals('production-db'));
      expect(deserialized.sinceCursor, equals(12000));
      expect(deserialized.limit, equals(50));
      expect(deserialized.collections, equals(['tasks', 'notes']));
    });

    test('handles missing optional fields', () {
      final request = PullRequest(
        dbId: 'test-db',
        sinceCursor: 0,
      );

      final bytes = request.toBytes();
      final deserialized = PullRequest.fromBytes(bytes);

      expect(deserialized.limit, equals(100)); // default
      expect(deserialized.collections, isNull);
    });
  });

  group('PullResponse', () {
    test('serializes and deserializes correctly', () {
      final response = PullResponse(
        ops: [
          SyncOperation(
            opId: 1001,
            dbId: 'production-db',
            deviceId: 'ios-device-7',
            collection: 'tasks',
            entityId: 'task-42',
            opType: OperationType.upsert,
            entityVersion: 3,
            entityCbor: Uint8List.fromList([0xa1, 0x61, 0x61, 0x01]),
            timestampMs: 1702569600000,
          ),
        ],
        nextCursor: 12346,
        hasMore: false,
      );

      final bytes = response.toBytes();
      final deserialized = PullResponse.fromBytes(bytes);

      expect(deserialized.ops.length, equals(1));
      expect(deserialized.ops[0].opId, equals(1001));
      expect(deserialized.ops[0].collection, equals('tasks'));
      expect(deserialized.nextCursor, equals(12346));
      expect(deserialized.hasMore, isFalse);
    });
  });

  group('PushRequest', () {
    test('serializes and deserializes correctly', () {
      final request = PushRequest(
        dbId: 'production-db',
        deviceId: 'android-a92f1',
        ops: [
          SyncOperation(
            opId: 5001,
            dbId: 'production-db',
            deviceId: 'android-a92f1',
            collection: 'notes',
            entityId: 'note-99',
            opType: OperationType.upsert,
            entityVersion: 1,
            entityCbor: Uint8List.fromList([0xa1, 0x62, 0x69, 0x64]),
            timestampMs: 1702569610000,
          ),
        ],
      );

      final bytes = request.toBytes();
      final deserialized = PushRequest.fromBytes(bytes);

      expect(deserialized.dbId, equals('production-db'));
      expect(deserialized.deviceId, equals('android-a92f1'));
      expect(deserialized.ops.length, equals(1));
      expect(deserialized.ops[0].opId, equals(5001));
    });
  });

  group('PushResponse', () {
    test('serializes and deserializes without conflicts', () {
      final response = PushResponse(
        acknowledgedUpToOpId: 5001,
        conflicts: [],
      );

      final bytes = response.toBytes();
      final deserialized = PushResponse.fromBytes(bytes);

      expect(deserialized.acknowledgedUpToOpId, equals(5001));
      expect(deserialized.conflicts, isEmpty);
      expect(deserialized.isFullyAccepted, isTrue);
    });

    test('serializes and deserializes with conflicts', () {
      final response = PushResponse(
        acknowledgedUpToOpId: 5000,
        conflicts: [
          Conflict(
            collection: 'notes',
            entityId: 'note-99',
            clientOp: SyncOperation(
              opId: 5001,
              dbId: 'production-db',
              deviceId: 'android-a92f1',
              collection: 'notes',
              entityId: 'note-99',
              opType: OperationType.upsert,
              entityVersion: 1,
              entityCbor: Uint8List.fromList([0xa1]),
              timestampMs: 1702569610000,
            ),
            serverState: ServerState(
              entityVersion: 2,
              entityCbor: Uint8List.fromList([0xa2]),
            ),
          ),
        ],
      );

      final bytes = response.toBytes();
      final deserialized = PushResponse.fromBytes(bytes);

      expect(deserialized.acknowledgedUpToOpId, equals(5000));
      expect(deserialized.conflicts.length, equals(1));
      expect(deserialized.conflicts[0].collection, equals('notes'));
      expect(deserialized.conflicts[0].serverState.entityVersion, equals(2));
      expect(deserialized.isFullyAccepted, isFalse);
    });
  });
}
