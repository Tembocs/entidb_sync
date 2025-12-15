# EntiDB Sync - TODO

**Last Updated:** 2025-12-15

---

## 🔴 High Priority (Must Fix)

### 1. Static Analysis Warnings (411 issues)

**Problem:** The codebase has 411 `info`-level warnings that will cause CI to fail with `--fatal-infos`. This also violates the project's own documentation requirements in `.github/copilot-instructions.md`.

**Issues breakdown:**
| Issue Type | Count |
|------------|-------|
| `public_member_api_docs` | ~60 |
| `sort_constructors_first` | ~50 |
| `prefer_const_constructors` | ~30 |
| `always_put_required_named_parameters_first` | ~20 |
| `avoid_redundant_argument_values` | ~15 |

**Solution:**
- Add `///` documentation comments to all public APIs
- Reorder constructors to appear before other members in classes
- Add `const` keyword to constructor invocations where applicable
- Reorder named parameters (required before optional)
- Remove redundant default argument values

**Files most affected:**
- `packages/entidb_sync_server/lib/src/db/entidb_sync_service.dart`
- `packages/entidb_sync_server/lib/src/metrics/prometheus_metrics.dart`
- `packages/entidb_sync_server/lib/src/middleware/*.dart`
- `packages/entidb_sync_protocol/lib/src/models/*.dart`

---

### 2. Server Uses In-Memory Storage by Default

**Problem:** The server entry point (`bin/server.dart`) uses `SyncService` which is in-memory only. All data is lost on server restart.

```dart
// Current (data lost on restart):
final syncService = SyncService();
```

**Solution:** Switch to `EntiDBSyncService` for persistent storage:

```dart
// Persistent storage:
final db = await EntiDB.open(path: config.dbPath);
final syncService = await EntiDBSyncService.create(db);
```

**File:** `packages/entidb_sync_server/bin/server.dart`

---

### 3. WAL Observation Uses Internal EntiDB Imports

**Problem:** The client imports internal EntiDB modules, creating tight coupling that may break on EntiDB updates.

```dart
// Fragile internal imports:
import 'package:entidb/src/engine/wal/wal_constants.dart';
import 'package:entidb/src/engine/wal/wal_reader.dart';
import 'package:entidb/src/engine/wal/wal_record.dart';
```

**Solution:**
1. Create a public WAL observation API in EntiDB core (preferred)
2. Or wrap internal imports in a single abstraction layer with version checks

**File:** `packages/entidb_sync_client/lib/src/oplog/sync_oplog_service_impl.dart`

---

## 🟡 Medium Priority (Should Fix)

### 4. No True End-to-End Integration Tests

**Problem:** Tests create `SyncOperation` manually with hand-crafted CBOR bytes. No tests actually:
1. Open an EntiDB database
2. Insert/update/delete data
3. Observe changes flowing through WAL → oplog → sync → server

**Solution:** Add integration test that:
```dart
test('full pipeline: EntiDB change → WAL → oplog → server', () async {
  final db = await EntiDB.open(path: tempPath);
  final oplogService = SyncOplogServiceImpl(config: OplogConfig(...));
  await oplogService.start();
  
  // Insert data
  final collection = await db.collection('users');
  await collection.insert({'name': 'Alice'});
  
  // Verify operation emitted
  final op = await oplogService.changeStream.first;
  expect(op.collection, 'users');
  expect(op.opType, OperationType.upsert);
});
```

**Location:** `packages/entidb_sync_client/test/integration/`

---

### 5. Print Statements in Production Code

**Problem:** `bin/server.dart` uses `print()` which violates `avoid_print` lint rule.

```dart
// Current:
print('$time [${record.level.name}] ${record.loggerName}: ${record.message}');
```

**Solution:** Use structured logging throughout:
```dart
// Fixed:
log.info('${record.loggerName}: ${record.message}');
```

**File:** `packages/entidb_sync_server/bin/server.dart`

---

### 6. Generic Error Responses in Endpoints

**Problem:** All endpoint errors return HTTP 400, no distinction between client and server errors.

```dart
} catch (e) {
  return _errorResponse(400, 'Invalid pull request: $e');  // Always 400
}
```

**Solution:** Differentiate error types:
```dart
} on FormatException catch (e) {
  return _errorResponse(400, 'Invalid request format: $e');
} on StateError catch (e) {
  return _errorResponse(409, 'Conflict: $e');
} catch (e) {
  return _errorResponse(500, 'Internal server error');
}
```

**File:** `packages/entidb_sync_server/lib/src/api/endpoints.dart`

---

### 7. No Protocol Version Enforcement in Handshake

**Problem:** Client can proceed with sync even if server version is incompatible. The `ProtocolVersion.isCompatible()` check exists but isn't enforced.

**Solution:** Add version check in `SyncEngine.sync()`:
```dart
final handshakeResponse = await _transport.handshake(_clientInfo);

// Enforce version compatibility
if (!ProtocolVersion.v1.isCompatible(handshakeResponse.protocolVersion)) {
  throw SyncException('Incompatible server version: ${handshakeResponse.protocolVersion}');
}
```

**File:** `packages/entidb_sync_client/lib/src/sync/sync_engine.dart`

---

## 🟢 Low Priority (Nice to Have)

### 8. Polling-Based WAL Observation

**Problem:** Client polls WAL every 100ms, which isn't optimal for mobile battery life.

```dart
_pollTimer = Timer.periodic(
  const Duration(milliseconds: 100),
  (_) => _processNewWalRecords(),
);
```

**Solution (future):**
- Add file system watcher support in EntiDB core
- Or implement adaptive polling (longer intervals when idle)

**File:** `packages/entidb_sync_client/lib/src/oplog/sync_oplog_service_impl.dart`

---

### 9. Simplistic Conflict Detection

**Problem:** Conflict detection is purely version-based, doesn't handle:
- Concurrent edits to different fields (could auto-merge)
- Merge conflicts (delta encoding exists but not used for resolution)

```dart
if (clientOp.entityVersion <= latestServerOp.entityVersion) {
  return Conflict(...);
}
```

**Solution (future):**
- Integrate delta encoding into conflict resolution
- Implement field-level merge when changes don't overlap
- Add `ConflictResolver` that uses `DeltaEncoder.diff()` for smart merging

**File:** `packages/entidb_sync_server/lib/src/sync/sync_service.dart`

---

### 10. Unnecessary Imports in Tests

**Problem:** Some test files import both protocol and server/client packages redundantly.

```dart
import 'package:entidb_sync_protocol/entidb_sync_protocol.dart';  // Unnecessary
import 'package:entidb_sync_server/entidb_sync_server.dart';       // Re-exports protocol
```

**Solution:** Remove redundant imports since server/client packages re-export protocol types.

**Files:**
- `packages/entidb_sync_server/test/sync_server_test.dart`
- `packages/entidb_sync_server/test/websocket_manager_test.dart`

---

## 🔮 Future Enhancements

### Planned Features

1. **Partial sync** — Sync only selected collections (beyond just filtering)
2. **Conflict-free replicated data types (CRDTs)** — For certain data patterns
3. **End-to-end encryption** — Client-side encryption before sync
4. **Multi-region support** — Geo-distributed sync servers
5. **Offline queue management UI** — Visualize pending operations

### Additional Ideas

6. **Adaptive sync intervals** — Adjust sync frequency based on network conditions
7. **Bandwidth throttling** — Limit sync data rate on metered connections
8. **Sync priority** — Prioritize certain collections/entities for sync
9. **Conflict resolution UI hooks** — Let users resolve conflicts manually
10. **Sync audit log** — Track sync history for debugging

---

## Progress Tracking

| Issue | Status | Assigned | Notes |
|-------|--------|----------|-------|
| #1 Static analysis | ❌ Not started | — | 411 warnings |
| #2 Persistent storage | ❌ Not started | — | `EntiDBSyncService` exists |
| #3 Internal imports | ❌ Not started | — | Needs EntiDB core changes |
| #4 E2E tests | ❌ Not started | — | |
| #5 Print statements | ❌ Not started | — | Quick fix |
| #6 Error responses | ❌ Not started | — | |
| #7 Version enforcement | ❌ Not started | — | |
| #8 WAL polling | 🔮 Future | — | Low priority |
| #9 Smart conflicts | 🔮 Future | — | Enhancement |
| #10 Redundant imports | ❌ Not started | — | Quick fix |

---

**Status Legend:**
- ✅ Complete
- 🔨 In Progress
- ❌ Not Started
- 🔮 Future Enhancement
- ⚠️ Blocked