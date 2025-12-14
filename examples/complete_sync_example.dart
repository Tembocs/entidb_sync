#!/usr/bin/env dart

/// End-to-End Sync Example
///
/// Demonstrates a complete sync workflow:
/// 1. Start a sync server
/// 2. Create sync components
/// 3. Perform manual sync operations
/// 4. Watch multi-device sync
///
/// Run this example:
/// ```bash
/// cd examples
/// dart pub get
/// dart run complete_sync_example.dart
/// ```
library;

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:entidb_sync_client/entidb_sync_client.dart';
import 'package:entidb_sync_server/entidb_sync_server.dart';
import 'package:logging/logging.dart';
import 'package:shelf/shelf.dart' as shelf;
import 'package:shelf/shelf_io.dart' as io;
import 'package:uuid/uuid.dart';

Future<void> main() async {
  // Configure logging
  _setupLogging();
  final log = Logger('Example');

  log.info('EntiDB Sync - Complete Example');
  log.info('===============================\n');

  // Create temporary directory for queue
  final tempDir = await Directory.systemTemp.createTemp('entidb_sync_example_');
  final queuePath = '${tempDir.path}/queue';

  try {
    // ========================================
    // 1. Start the sync server
    // ========================================
    log.info('Starting sync server...');

    final syncService = SyncService();
    final router = createSyncRouter(syncService);

    // No auth for this example (development mode)
    final handler = const shelf.Pipeline()
        .addMiddleware(createLoggingMiddleware(log))
        .addMiddleware(createCorsMiddleware())
        .addHandler(router.call);

    final server = await io.serve(handler, 'localhost', 0);
    final serverUrl = Uri.parse('http://localhost:${server.port}');
    log.info('Server running at $serverUrl\n');

    // ========================================
    // 2. Set up Device 1
    // ========================================
    log.info('Setting up Device 1...');

    final device1Id = const Uuid().v4();

    // Create transport config
    final transportConfig1 = TransportConfig(
      serverUrl: serverUrl,
      dbId: 'example-db',
      deviceId: device1Id,
    );
    final transport1 = SyncHttpTransport(config: transportConfig1);

    // Create client info
    final clientInfo1 = ClientInfo(
      platform: 'windows',
      appVersion: '1.0.0',
    );

    // Create sync engine
    final engine1 = SyncEngine(
      transport: transport1,
      clientInfo: clientInfo1,
    );

    // Create offline queue for device 1
    final queue1Path = '$queuePath/device1';
    await Directory(queue1Path).create(recursive: true);
    final queue1 = OfflineQueue(storagePath: queue1Path);
    await queue1.open();

    log.info('Device 1 configured (ID: ${device1Id.substring(0, 8)}...)\n');

    // ========================================
    // 3. Device 1 creates some operations
    // ========================================
    log.info('Device 1 creating local operations...');

    // Simulate local database operations
    for (var i = 1; i <= 3; i++) {
      final op = SyncOperation(
        opId: i,
        dbId: 'example-db',
        deviceId: device1Id,
        collection: 'users',
        entityId: 'user-$i',
        entityVersion: DateTime.now().millisecondsSinceEpoch,
        opType: OperationType.upsert,
        entityCbor: Uint8List.fromList([0xA1, 0x64, 0x6E, 0x61, 0x6D, 0x65, 
            0x66, 0x55, 0x73, 0x65, 0x72, 0x20 + i]), // CBOR: {"name": "User X"}
        timestampMs: DateTime.now().millisecondsSinceEpoch,
      );
      
      await queue1.enqueue(op);
      log.info('  Created user-$i');
    }
    log.info('');

    // ========================================
    // 4. Device 1 syncs with server
    // ========================================
    log.info('Device 1 syncing with server...');

    // Wire up the engine to get pending ops from queue
    engine1.onGetPendingOperations = (sinceOpId) async {
      return queue1.getPending(sinceOpId: sinceOpId);
    };

    final result1 = await engine1.sync();
    log.info('Device 1 sync result: ${result1.pushedCount} pushed, '
        '${result1.pulledCount} pulled\n');

    // Acknowledge synced operations
    if (result1.isSuccess) {
      await queue1.acknowledge(engine1.localCursor);
    }

    // ========================================
    // 5. Set up Device 2
    // ========================================
    log.info('Setting up Device 2...');

    final device2Id = const Uuid().v4();

    final transportConfig2 = TransportConfig(
      serverUrl: serverUrl,
      dbId: 'example-db',
      deviceId: device2Id,
    );
    final transport2 = SyncHttpTransport(config: transportConfig2);

    final clientInfo2 = ClientInfo(
      platform: 'android',
      appVersion: '1.0.0',
    );

    final engine2 = SyncEngine(
      transport: transport2,
      clientInfo: clientInfo2,
    );

    log.info('Device 2 configured (ID: ${device2Id.substring(0, 8)}...)\n');

    // ========================================
    // 6. Device 2 pulls operations from server
    // ========================================
    log.info('Device 2 pulling from server...');

    // Track pulled operations
    final pulledOps = <SyncOperation>[];
    engine2.onApplyOperation = (op) async {
      pulledOps.add(op);
      log.info('  Device 2 received: ${op.collection}/${op.entityId}');
    };

    final result2 = await engine2.sync();
    log.info('\nDevice 2 sync result: ${result2.pulledCount} pulled\n');

    // ========================================
    // 7. Show final stats
    // ========================================
    log.info('Final Statistics:');
    log.info('  Server oplog size: ${syncService.oplogSize}');
    log.info('  Device 1 queue: ${queue1.length} pending');
    log.info('  Device 2 received: ${pulledOps.length} operations');

    // ========================================
    // 8. Cleanup
    // ========================================
    log.info('\nCleaning up...');

    await queue1.close();
    engine1.dispose();
    engine2.dispose();
    await server.close();

    log.info('\n✅ Example completed successfully!');
    log.info('   Demonstrated:');
    log.info('   - Server startup with middleware');
    log.info('   - Offline queue for pending operations');
    log.info('   - Push sync from Device 1');
    log.info('   - Pull sync to Device 2');
    log.info('   - Multi-device synchronization');
  } catch (e, stack) {
    log.severe('Example failed', e, stack);
  } finally {
    // Cleanup temp directory
    await tempDir.delete(recursive: true);
  }
}

void _setupLogging() {
  Logger.root.level = Level.INFO;
  Logger.root.onRecord.listen((record) {
    final time = record.time.toIso8601String().substring(11, 23);
    final level = record.level.name.padRight(7);
    // ignore: avoid_print
    print('$time [$level] ${record.loggerName}: ${record.message}');
  });
}
