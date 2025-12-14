# EntiDB Sync

**Offline-first synchronization for EntiDB databases**

[![Dart SDK](https://img.shields.io/badge/Dart-3.10.1%2B-blue.svg)](https://dart.dev)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

---

## Overview

EntiDB Sync provides synchronization capabilities for [EntiDB](https://github.com/Tembocs/entidb), enabling:

- **Offline-first** operation with automatic sync when online
- **Conflict detection** with pluggable resolution strategies
- **CBOR-native** protocol for efficient data transfer
- **Client-side** sync engine (no server code in clients)
- **Reference server** implementation in Dart

---

## Architecture

This repository contains three packages:

```
packages/
├─ entidb_sync_protocol/    # Shared protocol definitions (CBOR codecs)
├─ entidb_sync_client/       # Client-side sync engine
└─ entidb_sync_server/       # Reference HTTP sync server
```

### Key Concepts

- **EntiDB WAL** → Physical transaction log (crash recovery)
- **Sync Oplog** → Logical replication log (synchronization)
- **Pull-then-Push** → Sync cycle ensures consistency
- **Server Authority** → Conflicts resolved server-side (by policy)

---

## Quick Start

### Client Usage

```dart
import 'package:entidb/entidb.dart';
import 'package:entidb_sync_client/entidb_sync_client.dart';

void main() async {
  // Open EntiDB database
  final db = await EntiDB.open(path: './myapp.db');
  
  // Configure sync
  final sync = EntiDBSync(
    db: db,
    config: SyncConfig(
      serverUrl: Uri.parse('https://sync.example.org'),
      dbId: 'my-database',
      deviceId: 'device-123',
      authTokenProvider: () async => getAuthToken(),
    ),
  );
  
  // Start syncing
  await sync.start();
  
  // Work offline - changes are queued
  final tasks = await db.collection<Task>('tasks', fromMap: Task.fromMap);
  await tasks.insert(Task(title: 'Sync this task'));
  
  // Sync happens automatically when online
}
```

### Server Setup

```bash
cd packages/entidb_sync_server
dart run bin/server.dart
```

Server runs on port 8080 by default. See [server documentation](packages/entidb_sync_server/README.md) for configuration.

---

## Documentation

### Getting Started
- **[Quick Start Guide](doc/quickstart.md)** ⭐ - Get up and running in 15 minutes
- **[Project Structure](doc/project_structure.md)** - Visual overview of the codebase
- **[Implementation Status](doc/implementation_status.md)** - Current progress and roadmap

### Technical Documentation
- **[Architecture](doc/architecture.md)** - Comprehensive design specification
- **[Repository Organization](doc/repository_organization.md)** - Monorepo structure and timeline
- **[Protocol Test Vectors](doc/protocol_test_vectors.md)** - CBOR examples for validation

### Development
- **[Contributing Guide](CONTRIBUTING.md)** - How to contribute
- **[Changelog](CHANGELOG.md)** - Version history

### Package Documentation
- [entidb_sync_protocol](packages/entidb_sync_protocol/README.md) - Protocol models
- [entidb_sync_client](packages/entidb_sync_client/README.md) - Client sync engine
- [entidb_sync_server](packages/entidb_sync_server/README.md) - Reference server

---

## Project Status

**Current Phase:** Foundation (Weeks 1-2)

- ✅ Architecture defined
- ✅ Package structure scaffolded
- ✅ Protocol test vectors documented
- 🚧 Protocol models implementation
- 📋 Client sync engine
- 📋 Reference server

See [repository_organization.md](doc/repository_organization.md) for the full roadmap.

---

## Development

### Prerequisites

- **Dart SDK 3.10.1 or higher** (required by EntiDB)
  - Upgrade with: `dart channel stable && dart upgrade`
  - Verify with: `dart --version`
- EntiDB (automatically included via git dependency)

### Setup

```bash
# Clone repository
git clone https://github.com/Tembocs/entidb_sync.git
cd entidb_sync

# Get dependencies for all packages
cd packages/entidb_sync_protocol && dart pub get && cd ../..
cd packages/entidb_sync_client && dart pub get && cd ../..
cd packages/entidb_sync_server && dart pub get && cd ../..
```

### Running Tests

```bash
# Protocol tests
cd packages/entidb_sync_protocol
dart test

# Client tests
cd packages/entidb_sync_client
dart test

# Server tests
cd packages/entidb_sync_server
dart test
```

---

## Design Principles

1. **EntiDB Purity:** Core database has no sync knowledge
2. **Offline-First:** Local operations never block on network
3. **Explicit Configuration:** No server discovery, no magic
4. **CBOR Native:** Reuses EntiDB's internal encoding
5. **Pluggable Conflicts:** Application defines resolution

---

## Contributing

Contributions welcome! Please read [CONTRIBUTING.md](CONTRIBUTING.md) first.

### Key Areas for Contribution

- Protocol model implementations
- Client sync engine
- Conflict resolution strategies
- Example applications
- Documentation improvements

---

## Related Projects

- **[EntiDB](https://github.com/Tembocs/entidb)** - Core embedded database
- **[CBOR](https://pub.dev/packages/cbor)** - Binary encoding library

---

## License

MIT License - see [LICENSE](LICENSE) file for details.

---

## Support

- **Issues:** [GitHub Issues](https://github.com/Tembocs/entidb_sync/issues)
- **Discussions:** [GitHub Discussions](https://github.com/Tembocs/entidb_sync/discussions)
- **EntiDB Core:** [EntiDB Repository](https://github.com/Tembocs/entidb)

---

**Maintained by the EntiDB Team**
