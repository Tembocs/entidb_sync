# Repository Structure

---

## Current State

> **Project Status:** Foundation Phase
>
> - ✅ **EntiDB core** is complete and operational at https://github.com/Tembocs/entidb
> - 🚧 **This repository** (`entidb_sync`) will house the synchronization layer
> - 📋 Packages are being scaffolded according to the structure below

---

## Short, definitive answer

> **Yes.**
> The sync engine **and** the reference sync server should live in the same repository,
> **`entidb_sync`**, as two *separate artifacts*.

They:

* Share protocol definitions
* Share CBOR schemas
* Share test vectors
* Share language (Dart)

But:

* They **do not depend on each other at runtime**
* They **never collapse into one component**

---

## The correct mental model

```
entidb_sync/
├─ packages/
│  ├─ entidb_sync_protocol/
│  │  ├─ lib/
│  │  │  ├─ models/
│  │  │  │  ├─ sync_operation.dart      # Logical replication record
│  │  │  │  ├─ conflict.dart            # Conflict representation
│  │  │  │  ├─ cursor.dart              # Sync progress tracking
│  │  │  │  └─ sync_config.dart         # Client configuration
│  │  │  ├─ cbor/
│  │  │  │  ├─ encoders.dart            # CBOR serialization
│  │  │  │  └─ decoders.dart            # CBOR deserialization
│  │  │  ├─ protocol_version.dart       # Version negotiation
│  │  │  └─ entidb_sync_protocol.dart   # Barrel export
│  │  ├─ test/
│  │  │  └─ protocol_test.dart
│  │  └─ pubspec.yaml                   # Deps: cbor, meta
│  │
│  ├─ entidb_sync_client/
│  │  ├─ lib/
│  │  │  ├─ src/
│  │  │  │  ├─ oplog/
│  │  │  │  │  ├─ sync_oplog_service.dart   # WAL observer
│  │  │  │  │  └─ operation_transformer.dart # WAL -> SyncOp
│  │  │  │  ├─ transport/
│  │  │  │  │  ├─ sync_client.dart          # HTTPS client
│  │  │  │  │  ├─ retry_policy.dart         # Exponential backoff
│  │  │  │  │  └─ offline_queue.dart        # Pending ops storage
│  │  │  │  ├─ state/
│  │  │  │  │  ├─ sync_state.dart           # Client sync state
│  │  │  │  │  └─ cursor_manager.dart       # Local cursor tracking
│  │  │  │  ├─ conflict/
│  │  │  │  │  ├─ conflict_handler.dart     # Pluggable resolution
│  │  │  │  │  └─ resolvers.dart            # Built-in strategies
│  │  │  │  └─ sync_engine.dart             # Main orchestrator
│  │  │  └─ entidb_sync_client.dart         # Public API
│  │  ├─ test/
│  │  └─ pubspec.yaml                       # Deps: entidb, protocol, http
│  │
│  ├─ entidb_sync_server/
│  │  ├─ bin/
│  │  │  └─ server.dart                      # Server entry point
│  │  ├─ lib/
│  │  │  ├─ src/
│  │  │  │  ├─ api/
│  │  │  │  │  ├─ endpoints.dart             # Route handlers
│  │  │  │  │  ├─ handshake_handler.dart
│  │  │  │  │  ├─ pull_handler.dart
│  │  │  │  │  └─ push_handler.dart
│  │  │  │  ├─ auth/
│  │  │  │  │  └─ token_validator.dart       # Bearer token auth
│  │  │  │  ├─ sync/
│  │  │  │  │  ├─ server_oplog.dart          # Server operation log
│  │  │  │  │  ├─ conflict_detector.dart     # Version conflict check
│  │  │  │  │  └─ cursor_manager.dart        # Per-client cursors
│  │  │  │  ├─ db/
│  │  │  │  │  └─ entidb_provider.dart       # Server EntiDB instance
│  │  │  │  └─ config/
│  │  │  │      └─ server_config.dart        # Server configuration
│  │  │  └─ entidb_sync_server.dart
│  │  ├─ test/
│  │  └─ pubspec.yaml                       # Deps: entidb, protocol, shelf
│
├─ tools/
│  ├─ protocol_tests/
│  │  └─ test_vectors.dart                  # CBOR test data
│  └─ fixtures/
│      └─ sample_operations.json
│
├─ examples/
│  ├─ flutter_client/                       # Example Flutter app
│  └─ standalone_server/                    # Deployable server
│
├─ doc/
│  ├─ architecture.md                       # This document
│  ├─ repository_organization.md            # This document
│  ├─ protocol_test_vectors.md             # CBOR examples
│  └─ api/                                  # Generated docs
│
└─ README.md
```

This is **one repository**, multiple clearly scoped deliverables.

---

## Implementation Timeline

### ✅ Phase 0: Foundation (Complete)
- EntiDB core database engine exists at `Tembocs/entidb`
- CBOR serialization, WAL, transactions, encryption all operational
- Storage engine (PagedStorage), indexes (B-tree, Hash), query system complete
- Reference: 15K+ lines of production-ready Dart code

### 🚧 Phase 1: Sync Foundation (In Progress - Weeks 1-2)
**Create in `entidb_sync` repo:**
- [ ] Protocol package structure (`entidb_sync_protocol`)
- [ ] Sync oplog abstraction (observes EntiDB WAL)
- [ ] Shared CBOR schemas for `SyncOperation`, `Conflict`, cursors
- [ ] Protocol test vectors with CBOR examples

### 📋 Phase 2: Client Sync Engine (Weeks 3-6)
- [ ] Implement `SyncOplogService` (WAL observer)
- [ ] Build `SyncClient` with HTTPS transport
- [ ] Pull-then-push cycle implementation
- [ ] Offline queue management
- [ ] Conflict detection and handler interface
- [ ] Retry/backoff logic with exponential backoff

### 📋 Phase 3: Reference Server (Weeks 7-8)
- [ ] Dart HTTP server with shelf/dart_frog
- [ ] Server-side EntiDB instance integration
- [ ] Implement `/v1/handshake`, `/v1/pull`, `/v1/push` endpoints
- [ ] Cursor management and per-client state
- [ ] Server-side conflict detection

### 📋 Phase 4: Testing & Polish (Weeks 9-10)
- [ ] End-to-end sync tests (multi-client scenarios)
- [ ] Performance benchmarking (throughput, latency)
- [ ] Comprehensive API documentation
- [ ] Example applications (Flutter + server)
- [ ] Migration guide for existing EntiDB users

---

## Why this makes sense (and is not a mistake)

### 1. Single source of truth for the protocol

Having client and server together means:

* No protocol drift
* No duplicated schemas
* No “client says X, server expects Y”

This is especially important for **CBOR**, where silent incompatibilities are dangerous.

---

### 2. Dart-first, end-to-end consistency

Since you have chosen Dart intentionally:

* Shared `SyncOperation`, `Conflict`, cursor models
* Shared CBOR encoders/decoders
* Shared validation rules

This eliminates a *huge* class of bugs.

---

### 3. Clean separation still exists

**Repository co-location ≠ architectural coupling**.

The separation is enforced by:

* Package boundaries
* Dependency direction rules
* Build artifacts

---

## Mandatory separation rules (do not violate)

### Rule 1 — EntiDB core dependency direction

```
entidb
  ↑
entidb_sync_client
  ↑
entidb_sync_server
```

Never the reverse.

---

### Rule 2 — Server never imports client sync engine

The server:

* Uses EntiDB
* Uses protocol models
* Does **not** use EntiDB_Sync client logic

---

### Rule 3 — Client never imports server logic

The client:

* Uses EntiDB
* Uses protocol models
* Uses HTTP transport

---

### Rule 4 — Protocol is dependency-free

The protocol package:

* Contains only data structures
* Contains CBOR encoding rules
* Contains versioning
* Contains no networking code

---

## Recommended repository layout (concrete)

```
entidb_sync/
├─ packages/
│  ├─ entidb_sync_protocol/
│  │  ├─ lib/
│  │  │  ├─ models/
│  │  │  │  ├─ sync_operation.dart
│  │  │  │  ├─ conflict.dart
│  │  │  │  └─ cursor.dart
│  │  │  ├─ cbor/
│  │  │  │  ├─ encoders.dart
│  │  │  │  └─ decoders.dart
│  │  │  └─ version.dart
│  │  └─ pubspec.yaml
│  │
│  ├─ entidb_sync_client/
│  │  ├─ lib/
│  │  │  ├─ engine/
│  │  │  ├─ transport/
│  │  │  ├─ state/
│  │  │  └─ entidb_sync.dart
│  │  └─ pubspec.yaml
│  │
│  ├─ entidb_sync_server/
│  │  ├─ bin/
│  │  │  └─ server.dart
│  │  ├─ lib/
│  │  │  ├─ api/
│  │  │  ├─ auth/
│  │  │  ├─ sync/
│  │  │  └─ entidb_provider.dart
│  │  └─ pubspec.yaml
│
├─ tools/
│  ├─ protocol_tests/
│  └─ fixtures/
│
└─ README.md
```

This structure:

* Scales
* Tests well
* Avoids circular dependencies
* Makes releases clean

---

## Publishing strategy (important)

* `entidb_sync_client` → published to `pub.dev`
* `entidb_sync_protocol` → published to `pub.dev`
* `entidb_sync_server` → **not** published (deployable service)

This keeps:

* Client lean
* Server free to evolve

---

## Final confirmation (no ambiguity)

> ✔ Yes — **one repository**
> ✔ Yes — **client + server together**
> ✔ Yes — **shared protocol package**
> ✔ No — **runtime coupling**
> ✔ No — **blurring responsibilities**

This is the **correct, professional, long-term maintainable approach**.

If you want next, I can:

* Generate the **monorepo scaffolding**
* Write initial `pubspec.yaml` files
* Create protocol test vectors
* Draft CI rules to enforce dependency direction

Just say the word.
