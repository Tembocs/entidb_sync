# Changelog

All notable changes to EntiDB Sync will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- Initial monorepo structure with three packages
- Protocol package with CBOR-encoded models
- SyncOperation, Conflict, Cursor, SyncConfig models
- Protocol versioning system (v1)
- SyncOplogService interface for WAL observation
- Server entry point with shelf HTTP server
- Comprehensive documentation:
  - Architecture specification
  - Repository organization
  - Protocol test vectors with CBOR examples
- Development tooling:
  - Analysis options
  - Git ignore rules
  - Contributing guide
- Basic examples

### Protocol (v1)
- Handshake endpoint for version negotiation
- Pull endpoint for receiving server operations
- Push endpoint for sending client operations
- CBOR encoding for efficient wire format
- JWT authentication (planned)

## [0.1.0] - TBD

Initial release (planned for Phase 1 completion)

### Planned Features
- Complete protocol implementation
- Basic sync client
- Reference server
- Conflict resolution strategies
- Offline queue management

---

## Version History

- `0.1.0` - First release (planned)
- Current: Development phase
