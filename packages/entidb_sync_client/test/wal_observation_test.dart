/// WAL Observation Integration Tests
///
/// Tests for the SyncOplogService WAL observation functionality.
library;

import 'dart:async';
import 'dart:io';

import 'package:entidb/entidb.dart' hide OperationType, DataOperationPayload;
// ignore: implementation_imports
import 'package:entidb/src/engine/wal/wal_writer.dart';
import 'package:entidb_sync_client/entidb_sync_client.dart';
import 'package:test/test.dart';

void main() {
  group('SyncOplogServiceImpl', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('oplog_test_');
    });

    tearDown(() async {
      // Give time for file handles to be released on Windows
      await Future<void>.delayed(const Duration(milliseconds: 100));
      try {
        await tempDir.delete(recursive: true);
      } catch (_) {
        // Ignore deletion errors on Windows due to file locking
      }
    });

    test('starts and observes WAL file', () async {
      // Create WAL file with some transactions
      final walConfig = WalConfig.development(tempDir.path);
      final writer = WalWriter(config: walConfig);
      await writer.open();

      // Write committed transaction
      final txnId = await writer.beginTransaction();
      await writer.logInsert(
        transactionId: txnId,
        collectionName: 'users',
        entityId: 'user-1',
        data: {'name': 'Alice', 'age': 30},
      );
      await writer.commitTransaction(txnId);

      await writer.close();

      // Find the WAL file
      final walFiles = tempDir
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('.log'))
          .toList();
      expect(walFiles, isNotEmpty);

      // Create oplog service
      final config = OplogConfig(
        walPath: walFiles.first.path,
        dbId: 'test-db',
        deviceId: 'test-device',
        persistState: false,
      );
      final oplogService = SyncOplogServiceImpl(config: config);

      // Collect emitted operations
      final operations = <SyncOperation>[];
      oplogService.changeStream.listen(operations.add);

      // Start observation
      await oplogService.start();

      // Wait for polling cycle
      await Future<void>.delayed(const Duration(milliseconds: 200));

      await oplogService.stop();

      // Should have captured the insert
      expect(operations, hasLength(1));
      expect(operations.first.collection, 'users');
      expect(operations.first.entityId, 'user-1');
      expect(operations.first.opType, OperationType.upsert);
    });

    test('skips internal collections', () async {
      final walConfig = WalConfig.development(tempDir.path);
      final writer = WalWriter(config: walConfig);
      await writer.open();

      // Write to internal collection
      final txn1 = await writer.beginTransaction();
      await writer.logInsert(
        transactionId: txn1,
        collectionName: '_internal_meta',
        entityId: 'meta-1',
        data: {'config': 'value'},
      );
      await writer.commitTransaction(txn1);

      // Write to normal collection
      final txn2 = await writer.beginTransaction();
      await writer.logInsert(
        transactionId: txn2,
        collectionName: 'products',
        entityId: 'prod-1',
        data: {'name': 'Widget'},
      );
      await writer.commitTransaction(txn2);

      await writer.close();

      final walFiles = tempDir
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('.log'))
          .toList();

      final config = OplogConfig(
        walPath: walFiles.first.path,
        dbId: 'test-db',
        deviceId: 'test-device',
        persistState: false,
      );
      final oplogService = SyncOplogServiceImpl(config: config);

      final operations = <SyncOperation>[];
      oplogService.changeStream.listen(operations.add);

      await oplogService.start();
      await Future<void>.delayed(const Duration(milliseconds: 200));
      await oplogService.stop();

      // Only products should be captured, not _internal_meta
      expect(operations, hasLength(1));
      expect(operations.first.collection, 'products');
    });

    test('ignores uncommitted transactions', () async {
      final walConfig = WalConfig.development(tempDir.path);
      final writer = WalWriter(config: walConfig);
      await writer.open();

      // Committed transaction
      final txn1 = await writer.beginTransaction();
      await writer.logInsert(
        transactionId: txn1,
        collectionName: 'orders',
        entityId: 'order-1',
        data: {'total': 100},
      );
      await writer.commitTransaction(txn1);

      // Aborted transaction
      final txn2 = await writer.beginTransaction();
      await writer.logInsert(
        transactionId: txn2,
        collectionName: 'orders',
        entityId: 'order-2',
        data: {'total': 200},
      );
      await writer.abortTransaction(txn2);

      await writer.close();

      final walFiles = tempDir
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('.log'))
          .toList();

      final config = OplogConfig(
        walPath: walFiles.first.path,
        dbId: 'test-db',
        deviceId: 'test-device',
        persistState: false,
      );
      final oplogService = SyncOplogServiceImpl(config: config);

      final operations = <SyncOperation>[];
      oplogService.changeStream.listen(operations.add);

      await oplogService.start();
      await Future<void>.delayed(const Duration(milliseconds: 200));
      await oplogService.stop();

      // Only order-1 from committed transaction
      expect(operations, hasLength(1));
      expect(operations.first.entityId, 'order-1');
    });

    test('detects delete operations', () async {
      final walConfig = WalConfig.development(tempDir.path);
      final writer = WalWriter(config: walConfig);
      await writer.open();

      final txnId = await writer.beginTransaction();
      await writer.logDelete(
        transactionId: txnId,
        collectionName: 'items',
        entityId: 'item-1',
        data: {'name': 'ToDelete'},
      );
      await writer.commitTransaction(txnId);

      await writer.close();

      final walFiles = tempDir
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('.log'))
          .toList();

      final config = OplogConfig(
        walPath: walFiles.first.path,
        dbId: 'test-db',
        deviceId: 'test-device',
        persistState: false,
      );
      final oplogService = SyncOplogServiceImpl(config: config);

      final operations = <SyncOperation>[];
      oplogService.changeStream.listen(operations.add);

      await oplogService.start();
      await Future<void>.delayed(const Duration(milliseconds: 200));
      await oplogService.stop();

      expect(operations, hasLength(1));
      expect(operations.first.opType, OperationType.delete);
      expect(operations.first.entityCbor, isNull);
    });

    test('persists and restores state', () async {
      final walConfig = WalConfig.development(tempDir.path);
      final writer = WalWriter(config: walConfig);
      await writer.open();

      final txnId = await writer.beginTransaction();
      await writer.logInsert(
        transactionId: txnId,
        collectionName: 'notes',
        entityId: 'note-1',
        data: {'text': 'Hello'},
      );
      await writer.commitTransaction(txnId);

      await writer.close();

      final walFiles = tempDir
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('.log'))
          .toList();

      final statePath = '${tempDir.path}/oplog_state.json';

      // First run
      final config1 = OplogConfig(
        walPath: walFiles.first.path,
        dbId: 'test-db',
        deviceId: 'test-device',
        persistState: true,
        statePath: statePath,
      );
      final oplogService1 = SyncOplogServiceImpl(config: config1);

      final operations1 = <SyncOperation>[];
      oplogService1.changeStream.listen(operations1.add);

      await oplogService1.start();
      await Future<void>.delayed(const Duration(milliseconds: 200));
      await oplogService1.stop();
      await oplogService1.dispose();

      expect(operations1, hasLength(1));

      // Verify state file exists
      expect(await File(statePath).exists(), isTrue);

      // Second run should not re-emit the same operation
      final config2 = OplogConfig(
        walPath: walFiles.first.path,
        dbId: 'test-db',
        deviceId: 'test-device',
        persistState: true,
        statePath: statePath,
      );
      final oplogService2 = SyncOplogServiceImpl(config: config2);

      final operations2 = <SyncOperation>[];
      oplogService2.changeStream.listen(operations2.add);

      await oplogService2.start();
      await Future<void>.delayed(const Duration(milliseconds: 200));
      await oplogService2.stop();
      await oplogService2.dispose();

      // Should be empty since we've already processed those operations
      expect(operations2, isEmpty);
    });

    test('getOperationsSince returns pending operations', () async {
      final walConfig = WalConfig.development(tempDir.path);
      final writer = WalWriter(config: walConfig);
      await writer.open();

      for (var i = 1; i <= 3; i++) {
        final txnId = await writer.beginTransaction();
        await writer.logInsert(
          transactionId: txnId,
          collectionName: 'items',
          entityId: 'item-$i',
          data: {'index': i},
        );
        await writer.commitTransaction(txnId);
      }

      await writer.close();

      final walFiles = tempDir
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('.log'))
          .toList();

      final config = OplogConfig(
        walPath: walFiles.first.path,
        dbId: 'test-db',
        deviceId: 'test-device',
        persistState: false,
      );
      final oplogService = SyncOplogServiceImpl(config: config);

      await oplogService.start();
      await Future<void>.delayed(const Duration(milliseconds: 200));

      // Get operations since opId 0
      final ops = await oplogService.getOperationsSince(sinceOpId: 0);
      expect(ops, hasLength(3));

      // Get operations since first operation
      final ops2 = await oplogService.getOperationsSince(sinceOpId: 1);
      expect(ops2, hasLength(2));

      await oplogService.stop();
    });

    test('acknowledge removes operations from buffer', () async {
      final walConfig = WalConfig.development(tempDir.path);
      final writer = WalWriter(config: walConfig);
      await writer.open();

      for (var i = 1; i <= 3; i++) {
        final txnId = await writer.beginTransaction();
        await writer.logInsert(
          transactionId: txnId,
          collectionName: 'items',
          entityId: 'item-$i',
          data: {'index': i},
        );
        await writer.commitTransaction(txnId);
      }

      await writer.close();

      final walFiles = tempDir
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('.log'))
          .toList();

      final config = OplogConfig(
        walPath: walFiles.first.path,
        dbId: 'test-db',
        deviceId: 'test-device',
        persistState: false,
      );
      final oplogService = SyncOplogServiceImpl(config: config);

      await oplogService.start();
      await Future<void>.delayed(const Duration(milliseconds: 200));

      // Acknowledge first 2 operations
      await oplogService.acknowledge(2);

      // Only third operation should remain
      final ops = await oplogService.getOperationsSince(sinceOpId: 0);
      expect(ops, hasLength(1));
      expect(ops.first.opId, 3);

      await oplogService.stop();
    });
  });

  group('OperationTransformerImpl', () {
    test('transforms insert payload to upsert operation', () {
      final transformer = OperationTransformerImpl();

      final payload = DataOperationPayload.insert(
        collectionName: 'users',
        entityId: 'user-1',
        data: {'name': 'Alice'},
      );

      final op = transformer.transform(
        walPayload: payload.toBytes(),
        opId: 1,
        dbId: 'test-db',
        deviceId: 'device-1',
      );

      expect(op, isNotNull);
      expect(op!.collection, 'users');
      expect(op.entityId, 'user-1');
      expect(op.opType, OperationType.upsert);
      expect(op.entityCbor, isNotNull);
    });

    test('transforms update payload to upsert operation', () {
      final transformer = OperationTransformerImpl();

      final payload = DataOperationPayload.update(
        collectionName: 'products',
        entityId: 'prod-1',
        before: {'price': 10},
        after: {'price': 20},
      );

      final op = transformer.transform(
        walPayload: payload.toBytes(),
        opId: 2,
        dbId: 'test-db',
        deviceId: 'device-1',
      );

      expect(op, isNotNull);
      expect(op!.opType, OperationType.upsert);
    });

    test('transforms delete payload to delete operation', () {
      final transformer = OperationTransformerImpl();

      final payload = DataOperationPayload.delete(
        collectionName: 'orders',
        entityId: 'order-1',
        data: {'status': 'pending'},
      );

      final op = transformer.transform(
        walPayload: payload.toBytes(),
        opId: 3,
        dbId: 'test-db',
        deviceId: 'device-1',
      );

      expect(op, isNotNull);
      expect(op!.opType, OperationType.delete);
      expect(op.entityCbor, isNull);
    });

    test('skips internal collections', () {
      final transformer = OperationTransformerImpl();

      final payload = DataOperationPayload.insert(
        collectionName: '_sync_meta',
        entityId: 'meta-1',
        data: {'config': 'value'},
      );

      final op = transformer.transform(
        walPayload: payload.toBytes(),
        opId: 4,
        dbId: 'test-db',
        deviceId: 'device-1',
      );

      expect(op, isNull);
    });
  });
}
