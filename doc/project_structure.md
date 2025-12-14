# EntiDB Sync - Project Structure

This document provides a visual overview of the complete project structure.

## Directory Tree

```
entidb_sync/
│
├── 📄 README.md                    # Project overview and quick start
├── 📄 LICENSE                      # MIT license
├── 📄 CHANGELOG.md                 # Version history
├── 📄 CONTRIBUTING.md              # Developer guide
├── 📄 analysis_options.yaml        # Dart linting configuration
├── 📄 .gitignore                   # Git ignore rules
├── 🔧 setup.sh                     # Setup script (Linux/Mac)
├── 🔧 setup.bat                    # Setup script (Windows)
│
├── 📁 doc/                          # Documentation
│   ├── architecture.md              # Complete architecture specification
│   ├── repository_organization.md   # Monorepo structure and timeline
│   ├── protocol_test_vectors.md     # CBOR examples and test cases
│   └── implementation_status.md     # Current progress and roadmap
│
├── 📁 packages/                     # Monorepo packages
│   │
│   ├── 📦 entidb_sync_protocol/     # Protocol package (shared)
│   │   ├── pubspec.yaml             # Dependencies: cbor, meta
│   │   ├── lib/
│   │   │   ├── entidb_sync_protocol.dart  # Barrel export
│   │   │   └── src/
│   │   │       ├── models/
│   │   │       │   ├── sync_operation.dart  # Core sync record
│   │   │       │   ├── conflict.dart        # Conflict representation
│   │   │       │   ├── cursor.dart          # Progress tracking
│   │   │       │   └── sync_config.dart     # Client configuration
│   │   │       ├── cbor/
│   │   │       │   ├── encoders.dart        # CBOR encoding utilities
│   │   │       │   └── decoders.dart        # CBOR decoding utilities
│   │   │       └── protocol_version.dart    # Version management
│   │   └── test/
│   │       └── protocol_test.dart           # Protocol validation tests
│   │
│   ├── 📦 entidb_sync_client/       # Client package
│   │   ├── pubspec.yaml             # Dependencies: protocol, entidb, http
│   │   ├── lib/
│   │   │   ├── entidb_sync_client.dart  # Barrel export
│   │   │   └── src/
│   │   │       ├── oplog/
│   │   │       │   └── sync_oplog_service.dart  # WAL observer interface
│   │   │       ├── sync/
│   │   │       │   └── sync_client.dart         # Main sync engine (stub)
│   │   │       ├── storage/
│   │   │       │   └── cursor_storage.dart      # Persistence (stub)
│   │   │       └── offline/
│   │   │           └── offline_queue.dart       # Offline ops (stub)
│   │   └── test/
│   │       └── sync_client_test.dart            # Client tests
│   │
│   └── 📦 entidb_sync_server/       # Server package
│       ├── pubspec.yaml             # Dependencies: protocol, entidb, shelf
│       ├── bin/
│       │   └── server.dart          # HTTP server entry point
│       ├── lib/
│       │   ├── entidb_sync_server.dart  # Barrel export
│       │   └── src/
│       │       ├── handlers/
│       │       │   └── sync_handler.dart        # Endpoint handlers (stub)
│       │       ├── middleware/
│       │       │   └── auth_middleware.dart     # JWT auth (stub)
│       │       └── services/
│       │           └── sync_service.dart        # Business logic (stub)
│       └── test/
│           └── sync_server_test.dart            # Server tests
│
└── 📁 examples/                     # Example applications
    ├── README.md                    # Examples overview
    └── basic_client.dart            # Simple sync client example
```

## Package Dependency Graph

```
┌──────────────────────┐
│  entidb_sync_server  │
│   (server package)   │
└──────────┬───────────┘
           │ depends on
           ├────────────────────────┐
           │                        │
           ▼                        ▼
┌──────────────────────┐   ┌────────────────────┐
│  entidb_sync_client  │   │ entidb_sync_protocol│
│   (client package)   │──▶│  (protocol package) │
└──────────────────────┘   └────────────────────┘
           │                        │
           └────────┬───────────────┘
                    │ both depend on
                    ▼
           ┌─────────────────┐
           │      entidb      │
           │ (core database)  │
           └─────────────────┘
```

## Data Flow

```
┌─────────────────────────────────────────────────────────────┐
│                      CLIENT APPLICATION                      │
└────────────────────────────┬────────────────────────────────┘
                             │
                             ▼
┌─────────────────────────────────────────────────────────────┐
│                     entidb_sync_client                       │
│  ┌─────────────┐    ┌──────────────┐    ┌────────────────┐ │
│  │SyncOplogSvc │───▶│  SyncClient  │───▶│  HTTP Client   │ │
│  └──────┬──────┘    └──────────────┘    └────────┬───────┘ │
│         │                                          │         │
└─────────┼──────────────────────────────────────────┼─────────┘
          │                                          │
          │ observes WAL                    CBOR/HTTP│
          │                                          │
┌─────────▼─────────────┐               ┌────────────▼─────────┐
│       EntiDB          │               │  entidb_sync_server  │
│  (local database)     │               │   (remote server)    │
│                       │               │                      │
│  ┌─────────────────┐  │               │  ┌────────────────┐ │
│  │  Write-Ahead    │  │               │  │  EntiDB (hub)  │ │
│  │  Log (WAL)      │  │               │  │                │ │
│  └─────────────────┘  │               │  └────────────────┘ │
└───────────────────────┘               └──────────────────────┘
```

## File Size Overview

| Component | Files | Lines | Status |
|-----------|-------|-------|--------|
| **Documentation** | 5 | ~5,000 | ✅ Complete |
| **Protocol Package** | 8 | ~800 | ✅ Foundation |
| **Client Package** | 6 | ~500 | ✅ Interfaces |
| **Server Package** | 5 | ~200 | ✅ Scaffold |
| **Tests** | 3 | ~200 | ✅ Basic |
| **Examples** | 2 | ~100 | ✅ Stubs |
| **Tooling** | 5 | ~300 | ✅ Complete |
| **TOTAL** | **34** | **~7,100** | |

## Key Files Reference

### Must-Read First
1. [README.md](../README.md) - Start here
2. [doc/architecture.md](architecture.md) - Deep dive into design
3. [doc/implementation_status.md](implementation_status.md) - Current progress

### For Protocol Understanding
1. [doc/protocol_test_vectors.md](protocol_test_vectors.md) - CBOR examples
2. [packages/entidb_sync_protocol/lib/src/models/sync_operation.dart](../packages/entidb_sync_protocol/lib/src/models/sync_operation.dart) - Core model

### For Implementation
1. [packages/entidb_sync_client/lib/src/oplog/sync_oplog_service.dart](../packages/entidb_sync_client/lib/src/oplog/sync_oplog_service.dart) - Client interface
2. [packages/entidb_sync_server/bin/server.dart](../packages/entidb_sync_server/bin/server.dart) - Server entry point
3. [CONTRIBUTING.md](../CONTRIBUTING.md) - Development guide

## Technology Stack

```
┌─────────────────────────────────────────────────────┐
│                    Application Layer                 │
│              (Flutter, CLI, Web, etc.)               │
└─────────────────────┬───────────────────────────────┘
                      │
┌─────────────────────▼───────────────────────────────┐
│                 entidb_sync_client                   │
│        Dart ^3.10.1  •  packages: http, retry        │
└─────────────────────┬───────────────────────────────┘
                      │
┌─────────────────────▼───────────────────────────────┐
│              entidb_sync_protocol                    │
│         Dart ^3.10.1  •  packages: cbor              │
└─────────────────────┬───────────────────────────────┘
                      │
┌─────────────────────▼───────────────────────────────┐
│                     EntiDB                           │
│      Embedded Database  •  CBOR Native              │
└──────────────────────────────────────────────────────┘
                      │
┌─────────────────────▼───────────────────────────────┐
│                   File System                        │
│           (SQLite-like paged storage)                │
└──────────────────────────────────────────────────────┘
```

## Development Workflow

```
1. Setup Environment
   └─▶ Run setup.sh/setup.bat
       └─▶ Installs all dependencies

2. Read Documentation
   └─▶ doc/architecture.md
   └─▶ doc/implementation_status.md

3. Pick a Task
   └─▶ See Phase 1 roadmap
   └─▶ Check implementation_status.md

4. Implement with Tests
   └─▶ Write unit tests
   └─▶ Follow CONTRIBUTING.md

5. Validate
   └─▶ dart analyze
   └─▶ dart format .
   └─▶ dart test

6. Submit PR
   └─▶ With clear description
   └─▶ Reference issue if applicable
```

## Quick Navigation

### By Role

**👨‍💻 Developer**
- Start: [CONTRIBUTING.md](../CONTRIBUTING.md)
- Reference: [doc/architecture.md](architecture.md)
- Interface: [SyncOplogService](../packages/entidb_sync_client/lib/src/oplog/sync_oplog_service.dart)

**📚 Learning**
- Start: [README.md](../README.md)
- Examples: [examples/basic_client.dart](../examples/basic_client.dart)
- Protocol: [doc/protocol_test_vectors.md](protocol_test_vectors.md)

**🎯 Planning**
- Status: [doc/implementation_status.md](implementation_status.md)
- Roadmap: [doc/repository_organization.md](repository_organization.md)
- Changes: [CHANGELOG.md](../CHANGELOG.md)

---

*Last updated: Initial project setup*
