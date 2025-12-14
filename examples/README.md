# EntiDB Sync Examples

This directory contains example applications demonstrating EntiDB synchronization.

## Examples

### Standalone Server
Basic HTTP server for testing sync protocol.

Location: `standalone_server/`

### Flutter Client
Flutter app showing real-time sync with offline support.

Location: `flutter_client/` (to be added)

## Running Examples

### Start the standalone server:
```bash
cd standalone_server
dart run bin/server.dart
```

### Run tests:
```bash
dart test
```

## Learn More

- [Architecture Documentation](../../doc/architecture.md)
- [Protocol Test Vectors](../../doc/protocol_test_vectors.md)
- [SyncOplogService Interface](../../packages/entidb_sync_client/lib/src/oplog/sync_oplog_service.dart)
