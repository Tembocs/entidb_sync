# Developer Quick Start Guide

**Get up and running with EntiDB Sync development in 15 minutes**

---

## Prerequisites Checklist

- [ ] Dart SDK 3.10.1+ installed
- [ ] Git installed  
- [ ] Code editor (VS Code recommended)
- [ ] Basic understanding of Dart
- [ ] Familiarity with async/await patterns

### Check Your Dart Version

```bash
dart --version
# Should show 3.10.1 or higher
```

**Need to upgrade?**
```bash
dart channel stable
dart upgrade
```

---

## 5-Minute Setup

### 1. Clone Repository (1 min)

```bash
git clone https://github.com/Tembocs/entidb_sync.git
cd entidb_sync
```

### 2. Run Setup Script (2 min)

**Linux/Mac:**
```bash
chmod +x setup.sh
./setup.sh
```

**Windows:**
```cmd
setup.bat
```

This installs all dependencies for the three packages.

### 3. Verify Setup (2 min)

```bash
# Run protocol tests
dart test packages/entidb_sync_protocol/test

# Should show: All tests passed!
```

---

## Project Tour (5 Minutes)

### Package Overview

```
packages/
├── entidb_sync_protocol/  ← Shared models, CBOR encoding
├── entidb_sync_client/    ← Client sync engine  
└── entidb_sync_server/    ← Reference server
```

### Key Files to Know

1. **Protocol Models**
   ```
   packages/entidb_sync_protocol/lib/src/models/
   ├── sync_operation.dart  ← Core sync record with CBOR
   ├── conflict.dart        ← Conflict representation
   ├── cursor.dart          ← Progress tracking
   └── sync_config.dart     ← Client configuration
   ```

2. **Client Interface**
   ```
   packages/entidb_sync_client/lib/src/oplog/
   └── sync_oplog_service.dart  ← WAL observer (300+ lines docs)
   ```

3. **Server Entry Point**
   ```
   packages/entidb_sync_server/bin/
   └── server.dart  ← HTTP server scaffold
   ```

### Essential Documentation

| Document | Purpose | Read Time |
|----------|---------|-----------|
| [README.md](../README.md) | Project overview | 3 min |
| [architecture.md](architecture.md) | Deep technical design | 20 min |
| [protocol_test_vectors.md](protocol_test_vectors.md) | CBOR examples | 10 min |
| [implementation_status.md](implementation_status.md) | Current progress | 5 min |

---

## Understanding the Architecture (5 Minutes)

### The Big Picture

```
┌──────────────┐         ┌──────────────┐
│   Client     │◀───────▶│    Server    │
│  (Device 1)  │  CBOR   │   (EntiDB)   │
└──────────────┘ over HTTP└──────────────┘
       ▲                          ▲
       │ observes                 │ stores
       │                          │
┌──────▼──────┐           ┌──────▼──────┐
│  EntiDB WAL │           │EntiDB Server│
│   (local)   │           │  Database   │
└─────────────┘           └─────────────┘
```

### Key Concepts

**1. WAL vs Oplog**
- **WAL (Write-Ahead Log):** EntiDB's crash recovery log (physical)
- **Oplog (Operation Log):** Sync layer's logical operation stream

**2. CBOR Encoding**
- Binary encoding (RFC 8949)
- More efficient than JSON
- Native in EntiDB

**3. Operation-Based Sync**
- Each change = one `SyncOperation`
- Contains: entity data + metadata
- Immutable records

**4. Conflict Resolution**
- Detected via version numbers
- Multiple strategies available
- Server or client decides

### Data Flow

```
1. User writes to EntiDB
   └▶ EntiDB writes to WAL

2. SyncOplogService observes WAL
   └▶ Transforms to SyncOperation

3. SyncClient sends to server
   └▶ CBOR-encoded over HTTP

4. Server processes
   └▶ Stores in hub database
   └▶ Detects conflicts

5. Client pulls changes
   └▶ Applies to local database
```

---

## Your First Task (Choose One)

### Task 1: Add a Protocol Test (Easy - 30 min)

**Goal:** Add test for `Conflict` model

**Steps:**
1. Open: `packages/entidb_sync_protocol/test/protocol_test.dart`
2. Add new test group:
   ```dart
   group('Conflict', () {
     test('creates conflict correctly', () {
       final conflict = Conflict(
         collection: 'users',
         entityId: 'user-123',
         clientOp: /* create operation */,
         serverState: /* create server state */,
       );
       
       expect(conflict.collection, equals('users'));
       expect(conflict.entityId, equals('user-123'));
     });
   });
   ```
3. Run: `dart test packages/entidb_sync_protocol/test`

**Learn:** How models work, testing patterns

---

### Task 2: Implement CBOR Encoder (Medium - 2 hours)

**Goal:** Create utility function to encode handshake message

**Steps:**
1. Open: `packages/entidb_sync_protocol/lib/src/cbor/encoders.dart`
2. Add:
   ```dart
   import 'dart:typed_data';
   import 'package:cbor/cbor.dart';
   
   /// Encodes a handshake request.
   Uint8List encodeHandshakeRequest({
     required int clientVersion,
     required String dbId,
     required String deviceId,
   }) {
     final map = {
       'type': 'handshake_req',
       'version': clientVersion,
       'db_id': dbId,
       'device_id': deviceId,
     };
     
     final encoder = CborEncoder();
     encoder.writeMap(map);
     return Uint8List.fromList(encoder.output);
   }
   ```
3. Add test in `test/protocol_test.dart`
4. Validate against test vectors in `doc/protocol_test_vectors.md`

**Learn:** CBOR encoding, protocol messages

---

### Task 3: Start SyncOplogService Implementation (Hard - 4 hours)

**Goal:** Create basic WAL observer

**Steps:**
1. Create: `packages/entidb_sync_client/lib/src/oplog/sync_oplog_service_impl.dart`
2. Implement interface from `sync_oplog_service.dart`
3. Use EntiDB's internal APIs (may need to explore EntiDB repo)
4. Focus on:
   - Observing WAL changes
   - Creating `SyncOperation` from WAL entries
   - Emitting stream of operations

**Reference:**
- [EntiDB repository](https://github.com/Tembocs/entidb)
- Interface docs in `sync_oplog_service.dart`

**Learn:** EntiDB internals, stream programming

---

## Common Commands

### Development

```bash
# Format code
dart format .

# Analyze
dart analyze

# Run tests (all)
dart test

# Run tests (specific package)
dart test packages/entidb_sync_protocol/test

# Run tests (with coverage)
dart test --coverage=coverage
```

### Testing

```bash
# Run single test file
dart test packages/entidb_sync_protocol/test/protocol_test.dart

# Run tests with names matching pattern
dart test --name="SyncOperation"

# Verbose output
dart test --reporter=expanded
```

### Server

```bash
# Run server (when implemented)
cd packages/entidb_sync_server
dart run bin/server.dart

# Run on specific port
PORT=3000 dart run bin/server.dart
```

---

## Troubleshooting

### Issue: "SDK version error"

**Symptom:** `requires SDK version ^3.10.1`

**Solution:**
```bash
dart channel stable
dart upgrade
dart --version  # Verify ≥ 3.10.1
```

### Issue: "Package not found"

**Symptom:** `Could not resolve entidb_sync_protocol`

**Solution:**
```bash
# From repository root
cd packages/entidb_sync_protocol
dart pub get

cd ../entidb_sync_client
dart pub get
```

### Issue: "EntiDB git dependency fails"

**Symptom:** `Git error: Unable to resolve 'entidb'`

**Solution:**
1. Check internet connection
2. Verify GitHub access
3. Try: `dart pub cache clean`

### Issue: "Tests fail"

**Check:**
1. Dependencies installed? → `dart pub get`
2. Code formatted? → `dart format .`
3. No analysis errors? → `dart analyze`

---

## Getting Help

### 📚 Documentation
- Architecture questions → [architecture.md](architecture.md)
- Protocol details → [protocol_test_vectors.md](protocol_test_vectors.md)
- Current status → [implementation_status.md](implementation_status.md)

### 💬 Community
- GitHub Issues → Bug reports, feature requests
- GitHub Discussions → Questions, ideas
- Pull Requests → Code contributions

### 🔍 Code Examples
- See `examples/basic_client.dart`
- See test files in each package
- See protocol test vectors

---

## Next Steps

1. **Read Core Docs** (30 min)
   - [ ] [architecture.md](architecture.md) - Sections 1-6
   - [ ] [SyncOplogService interface](../packages/entidb_sync_client/lib/src/oplog/sync_oplog_service.dart)

2. **Pick a Task** (choose one above)
   - [ ] Add protocol test
   - [ ] Implement CBOR encoder
   - [ ] Start SyncOplogService

3. **Join Development**
   - [ ] Read [CONTRIBUTING.md](../CONTRIBUTING.md)
   - [ ] Check [implementation_status.md](implementation_status.md) for tasks
   - [ ] Submit your first PR!

---

## Quick Reference Card

### File Locations
| Need | Location |
|------|----------|
| Protocol models | `packages/entidb_sync_protocol/lib/src/models/` |
| Client interface | `packages/entidb_sync_client/lib/src/oplog/` |
| Server code | `packages/entidb_sync_server/bin/` |
| Tests | `packages/*/test/` |
| Documentation | `doc/` |

### Common Tasks
| Task | Command |
|------|---------|
| Setup | `./setup.sh` or `setup.bat` |
| Test | `dart test` |
| Format | `dart format .` |
| Analyze | `dart analyze` |
| Dependencies | `dart pub get` |

### Important URLs
- EntiDB Repo: https://github.com/Tembocs/entidb
- CBOR RFC: https://www.rfc-editor.org/rfc/rfc8949.html
- Dart Style: https://dart.dev/guides/language/effective-dart

---

**Ready to code? Pick a task above and start building! 🚀**

---

*Questions? See [CONTRIBUTING.md](../CONTRIBUTING.md) or open a GitHub Discussion.*
