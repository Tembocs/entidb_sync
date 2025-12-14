/// EntiDB Sync Client
///
/// Client-side synchronization engine for EntiDB databases.
///
/// Features:
/// - Offline-first operation with local queue
/// - Pull-then-push sync cycle
/// - Conflict detection and pluggable resolution
/// - Automatic retry with exponential backoff
/// - Observes EntiDB WAL for change tracking
/// - Real-time updates via Server-Sent Events (SSE)
///
/// Usage:
/// ```dart
/// final sync = EntiDBSync(
///   db: entidb,
///   config: SyncConfig(
///     serverUrl: Uri.parse('https://sync.example.org'),
///     dbId: 'my-database',
///     deviceId: 'device-123',
///   ),
/// );
///
/// await sync.start();
/// ```
library entidb_sync_client;

// Re-export protocol types for convenience
export 'package:entidb_sync_protocol/entidb_sync_protocol.dart';

// Oplog service (WAL observation)
export 'src/oplog/sync_oplog_service.dart';
export 'src/oplog/sync_oplog_service_impl.dart';

// Offline queue
export 'src/queue/offline_queue.dart';

// HTTP transport
export 'src/transport/http_transport.dart';

// Sync engine
export 'src/sync/sync_engine.dart';
export 'src/sync/sync_manager.dart';

// Conflict resolution
export 'src/conflict/resolvers.dart';

// SSE (Server-Sent Events) for real-time updates
export 'src/sse/sse_subscriber.dart';
