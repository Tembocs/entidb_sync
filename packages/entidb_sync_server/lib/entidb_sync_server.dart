/// EntiDB Sync Server
///
/// Reference HTTP server implementation for EntiDB synchronization.
///
/// Features:
/// - RESTful sync endpoints (handshake, pull, push)
/// - Server-side EntiDB instance for authoritative state
/// - Per-client cursor management
/// - Conflict detection and policy enforcement
/// - JWT authentication support
/// - Real-time updates via Server-Sent Events (SSE)
///
/// This is a reference implementation. Production deployments may
/// customize authentication, scaling, and deployment strategies.
library entidb_sync_server;

// Re-export protocol types for convenience
export 'package:entidb_sync_protocol/entidb_sync_protocol.dart';

// Configuration
export 'src/config/server_config.dart';

// Database
export 'src/db/entidb_sync_service.dart';

// Sync service (in-memory for testing)
export 'src/sync/sync_service.dart';

// API endpoints
export 'src/api/endpoints.dart';

// SSE (Server-Sent Events) for real-time updates
export 'src/sse/sse_manager.dart';

// Middleware
export 'src/middleware/auth_middleware.dart';
export 'src/middleware/compression_middleware.dart';
export 'src/middleware/cors_middleware.dart';
export 'src/middleware/logging_middleware.dart';
export 'src/middleware/rate_limit_middleware.dart';
