// TODO: Uncomment when packages are ready
// import 'package:entidb_sync_protocol/entidb_sync_protocol.dart';

/// Basic sync client example
///
/// Demonstrates:
/// - Connecting to sync server
/// - Performing handshake
/// - Pull/push operations
void main() async {
  print('EntiDB Sync Client Example');
  print('===========================\n');

  // Configuration
  final serverUrl = Uri.parse('http://localhost:8080');
  final dbId = 'example-db';
  final deviceId = 'example-device-001';

  print('Connecting to: $serverUrl');
  print('Database ID: $dbId');
  print('Device ID: $deviceId\n');

  // TODO: Initialize sync client when implementation is ready
  /*
  final config = SyncConfig(
    serverUrl: serverUrl,
    dbId: dbId,
    deviceId: deviceId,
    authTokenProvider: () async => 'dev-token',
    syncIntervalSeconds: 30,
  );

  final client = SyncClient(config);
  
  // Start automatic sync
  await client.start();
  
  print('Sync client started. Press Ctrl+C to stop.\n');
  
  // Listen for sync events
  client.stateStream.listen((state) {
    print('Sync state: $state');
  });
  
  // Keep running
  await Future.delayed(Duration(minutes: 5));
  
  await client.stop();
  */

  print('This example will be functional once SyncClient is implemented.');
  print('See packages/entidb_sync_client/lib/src/sync_client.dart');
}
