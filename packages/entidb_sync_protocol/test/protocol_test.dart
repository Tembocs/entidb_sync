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
}
