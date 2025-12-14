# EntiDB Sync - AI Coding Instructions

## Project Constraints (Non-Negotiable)

- **Dart-only project** — No other programming languages allowed in implementation
- **EntiDB-only database** — No dependency on any other database engine (SQLite, PostgreSQL, etc.)
- **Setup scripts in Python** — All automation/setup scripts must use Python, not Bash or Batch files

## Architecture Overview

This is a **Dart monorepo** implementing offline-first sync for [EntiDB](https://github.com/Tembocs/entidb) databases. The system uses **EntiDB as the single database engine everywhere** — both clients and server run EntiDB instances coordinated through sync.

```
packages/
├── entidb_sync_protocol/   # Pure protocol definitions (no I/O)
├── entidb_sync_client/     # Client sync engine (WAL → oplog → server)
└── entidb_sync_server/     # Reference HTTP server (Shelf-based)
```

**Data flow:** EntiDB WAL → `SyncOplogService` (transforms physical to logical) → `SyncEngine` (pull-then-push) → HTTP → Server

## Sync Engine State Machine

The `SyncEngine` operates as a state machine with these states:
```
idle → connecting → pulling → pushing → synced → (back to idle)
                ↘           ↘           ↘
                      error (can retry → connecting)
```

- **idle**: No sync in progress, waiting for trigger
- **connecting**: Establishing connection, performing handshake
- **pulling**: Fetching server operations since last cursor
- **pushing**: Sending local operations to server
- **synced**: Cycle complete, will return to idle
- **error**: Recoverable failure, can retry with backoff

Access state via `syncEngine.stateStream` for UI updates.

## Protocol Versioning

`ProtocolVersion` handles compatibility negotiation during handshake:
```dart
// Current version info
ProtocolVersion.v1.current      // e.g., 1
ProtocolVersion.v1.minSupported // e.g., 1

// Compatibility check
if (!ProtocolVersion.v1.isCompatible(serverVersion)) {
  throw ErrorResponse.versionMismatch(...);
}
```

Server advertises version in `/v1/version` endpoint. Client must check compatibility before sync.

## WAL to SyncOperation Mapping

The `OperationTransformerImpl` maps EntiDB WAL records to sync operations:

| WAL Field | SyncOperation Field | Notes |
|-----------|---------------------|-------|
| `DataOperationPayload.collectionName` | `collection` | Direct mapping |
| `DataOperationPayload.entityId` | `entityId` | Direct mapping |
| `DataOperationPayload.afterImage` | `entityCbor` | Re-encoded as CBOR bytes |
| `DataOperationPayload.afterImage == null` | `opType: delete` | No afterImage = deletion |
| `DataOperationPayload.afterImage != null` | `opType: upsert` | Has afterImage = insert/update |
| (generated) | `opId` | Monotonic per-device counter |
| (generated) | `entityVersion` | Timestamp-based for conflicts |

Collections starting with `_` (underscore) are skipped as internal/system collections.

## Critical Conventions

### CBOR-Native Protocol
All wire communication uses **CBOR (RFC 8949)**, not JSON. Protocol messages have `toBytes()`/`fromBytes()` methods:
```dart
// Correct pattern
final bytes = request.toBytes();           // Uint8List
final response = PullResponse.fromBytes(bytes);

// Encoders in: lib/src/cbor/encoders.dart
// Decoders in: lib/src/cbor/decoders.dart
```

### Package Dependencies
- **protocol** → standalone (no external deps except `cbor`, `meta`)
- **client** → depends on `protocol` + `entidb` (git dependency)
- **server** → depends on `protocol` + `entidb` + `shelf`

Both client and server re-export protocol types for convenience.

### Model Patterns
All protocol models are `@immutable` with:
- CBOR serialization via `toBytes()`/`fromBytes()` 
- Equality operators (`==`, `hashCode`)
- Factory constructors for common cases (e.g., `SyncCursor.initial()`)

### WAL Integration
The sync client observes EntiDB's WAL using types from `package:entidb/src/engine/wal/`:
- `WalReader`, `WalRecord`, `DataOperationPayload`, `Lsn`
- Two-pass processing: analyze committed transactions, then emit operations
- Polling-based (100ms) since EntiDB WAL doesn't support file watching

## Development Commands

```bash
# Install deps for all packages (must do each separately)
cd packages/entidb_sync_protocol && dart pub get
cd packages/entidb_sync_client && dart pub get  
cd packages/entidb_sync_server && dart pub get

# Run tests per-package
dart test packages/entidb_sync_protocol/test
dart test packages/entidb_sync_client/test
dart test packages/entidb_sync_server/test

# Analyze entire repo
dart analyze

# Run server
dart run packages/entidb_sync_server/bin/server.dart
```

## Key Implementation Patterns

### Error Handling
Use `ErrorResponse` for protocol errors with typed `SyncErrorCode`:
```dart
return ErrorResponse.authenticationFailed(message: 'Token expired');
return ErrorResponse.conflict('Version mismatch', details: '...');
```

### Conflict Resolution
Pluggable resolvers implement `ConflictResolver.resolve(Conflict)`:
- `ServerWinsResolver` (default, safest)
- `ClientWinsResolver`, `LastWriteWinsResolver`, `CustomResolver`

### Middleware (Server)
Shelf-based middleware in `lib/src/middleware/`:
- `createJwtAuthMiddleware()` — JWT validation with public path exclusions
- `createCorsMiddleware()` — configurable CORS
- `createLoggingMiddleware()` — request/response logging

### Server Configuration
Uses `ServerConfig.fromEnvironment()` for env-var based config:
- `HOST`, `PORT`, `DB_PATH`, `JWT_SECRET`
- `MAX_PULL_LIMIT`, `MAX_PUSH_BATCH_SIZE`

## Testing Patterns

Tests use `package:test` with group/test structure. Protocol tests validate CBOR round-tripping:
```dart
test('serializes and deserializes correctly', () {
  final op = SyncOperation(...);
  final bytes = op.toBytes();
  final restored = SyncOperation.fromBytes(bytes);
  expect(restored, equals(op));
});
```

## Code Style

- Strict analysis: `strict-casts`, `strict-inference`, `strict-raw-types`
- Conventional commits: `feat:`, `fix:`, `docs:`, `test:`, `refactor:`
- Library declarations use `library;` (unnamed) for internal modules
- Doc comments on all public APIs with usage examples
