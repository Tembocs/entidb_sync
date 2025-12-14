# Technical Decision Records (TDR)

This document records significant technical decisions made during EntiDB Sync development.

---

## TDR-001: Use CBOR for Wire Protocol

**Date:** 2024-01-15  
**Status:** ✅ Accepted  
**Deciders:** Core team

### Context
Need to choose a serialization format for sync protocol between clients and server.

### Options Considered

1. **JSON**
   - ✅ Human-readable
   - ✅ Well-supported
   - ❌ Verbose (larger payload)
   - ❌ No binary data support

2. **Protocol Buffers**
   - ✅ Efficient binary format
   - ✅ Schema validation
   - ❌ Requires code generation
   - ❌ Not native to EntiDB

3. **CBOR** (Chosen)
   - ✅ Compact binary format
   - ✅ Native to EntiDB
   - ✅ No code generation
   - ✅ RFC 8949 standard
   - ❌ Not human-readable

### Decision
Use **CBOR (RFC 8949)** for wire protocol.

### Rationale
- EntiDB already uses CBOR internally for serialization
- Efficient binary encoding (50-70% smaller than JSON)
- No impedance mismatch - same format end-to-end
- Standard with libraries in all languages
- Supports binary data natively

### Consequences
- Need CBOR encoders/decoders in protocol package
- Debugging requires CBOR diagnostic tools
- Test vectors must be provided in hex + diagnostic notation

---

## TDR-002: Oplog as Separate Layer Above WAL

**Date:** 2024-01-15  
**Status:** ✅ Accepted  
**Deciders:** Core team

### Context
EntiDB has a WAL for crash recovery. Need to decide if sync should use WAL directly or create a separate oplog.

### Options Considered

1. **Use WAL Directly**
   - ✅ No duplicate data
   - ✅ Simpler architecture
   - ❌ Couples sync to storage layer
   - ❌ WAL entries are physical (page-level)
   - ❌ WAL can be compacted/truncated

2. **Separate Oplog** (Chosen)
   - ✅ Logical operations (entity-level)
   - ✅ Stable, never truncated
   - ✅ Decoupled from storage
   - ✅ Can add sync-specific metadata
   - ❌ Additional storage overhead

### Decision
Create **separate oplog layer** that observes WAL and transforms entries.

### Rationale
- WAL is physical (page writes), oplog is logical (entity changes)
- Sync needs stable operation IDs that never get reused
- Allows adding sync-specific metadata (device ID, timestamps)
- Clear separation of concerns
- EntiDB can evolve storage independently

### Consequences
- Need `SyncOplogService` to observe WAL and transform entries
- Additional storage for oplog (but can be compacted separately)
- Oplog must be designed for efficient range queries (cursor-based)

---

## TDR-003: Monorepo with Three Packages

**Date:** 2024-01-15  
**Status:** ✅ Accepted  
**Deciders:** Core team

### Context
Need to organize code for protocol, client, and server components.

### Options Considered

1. **Single Package**
   - ✅ Simple versioning
   - ✅ Easy to work with
   - ❌ Can't use protocol without pulling in client/server deps
   - ❌ Coupling issues

2. **Separate Repos**
   - ✅ Full independence
   - ❌ Complex versioning
   - ❌ Hard to make cross-package changes
   - ❌ No shared CI/CD

3. **Monorepo** (Chosen)
   - ✅ Shared protocol package
   - ✅ Atomic cross-package changes
   - ✅ Unified CI/CD
   - ✅ Clear dependency graph
   - ❌ Slightly more complex setup

### Decision
Use **monorepo** with three packages:
- `entidb_sync_protocol` - Shared models and CBOR codecs
- `entidb_sync_client` - Client sync engine
- `entidb_sync_server` - Reference server

### Rationale
- Protocol is shared dependency, should be separate package
- Client and server have different dependencies
- Monorepo enables atomic protocol changes
- Easier testing and CI/CD
- Common pattern in Dart ecosystem

### Consequences
- Need path dependencies between packages
- Must manage versioning carefully
- Setup scripts needed for new developers
- Clear separation enforces good architecture

---

## TDR-004: Pull-Then-Push Sync Cycle

**Date:** 2024-01-15  
**Status:** ✅ Accepted  
**Deciders:** Core team

### Context
Need to decide sync cycle order and conflict detection timing.

### Options Considered

1. **Push-Then-Pull**
   - ✅ Client sees conflicts immediately
   - ❌ More conflicts (client is always behind)
   - ❌ Wastes bandwidth on rejected operations

2. **Pull-Then-Push** (Chosen)
   - ✅ Fewer conflicts (client is up-to-date)
   - ✅ Better bandwidth efficiency
   - ✅ Simpler conflict resolution
   - ❌ Client may have already shown stale data

3. **Bidirectional Simultaneous**
   - ✅ Fastest sync
   - ❌ Complex conflict handling
   - ❌ Race conditions

### Decision
Use **pull-then-push** cycle.

### Rationale
- Reduces conflict rate significantly
- Client applies server changes first, then pushes
- Server can still detect conflicts via version numbers
- Simpler implementation and reasoning
- Most common pattern in sync systems

### Consequences
- Sync cycle: handshake → pull → apply → push
- Client must handle merge of server changes before pushing
- Offline queue processed after pull completes

---

## TDR-005: Operation-Based (NOT State-Based) Sync

**Date:** 2024-01-15  
**Status:** ✅ Accepted  
**Deciders:** Core team

### Context
Choose between syncing operations (deltas) vs full state (snapshots).

### Options Considered

1. **State-Based Sync**
   - ✅ Simpler (just send current state)
   - ✅ Self-healing (state converges)
   - ❌ Can't track causality
   - ❌ Can't preserve concurrent edits
   - ❌ Large payloads

2. **Operation-Based Sync** (Chosen)
   - ✅ Efficient (only deltas)
   - ✅ Preserves operation order
   - ✅ Better conflict detection
   - ✅ Audit trail
   - ❌ Must handle operation ordering

### Decision
Use **operation-based sync** with `SyncOperation` records.

### Rationale
- Each write becomes a `SyncOperation` with:
  - Unique operation ID
  - Entity version number
  - Full entity data (CBOR)
  - Metadata (device, timestamp)
- Enables fine-grained conflict detection
- Smaller payloads (only changed entities)
- Provides audit trail
- Standard approach (similar to MongoDB, CouchDB)

### Consequences
- Need operation log storage
- Must handle operation ordering
- Conflicts detected via version numbers
- Can implement different conflict resolution strategies

---

## TDR-006: Server-Side Conflict Resolution

**Date:** 2024-01-15  
**Status:** ✅ Accepted  
**Deciders:** Core team

### Context
Decide where conflicts are detected and resolved.

### Options Considered

1. **Client-Side Resolution**
   - ✅ Works offline
   - ❌ Inconsistent resolution across clients
   - ❌ Server must trust client

2. **Server-Side Resolution** (Chosen)
   - ✅ Authoritative source of truth
   - ✅ Consistent resolution
   - ✅ Can enforce business rules
   - ❌ Client must handle rejection

3. **Hybrid**
   - ✅ Flexible
   - ❌ Complex implementation
   - ❌ Unclear ownership

### Decision
**Server detects and resolves** conflicts. Client can handle if needed.

### Rationale
- Server is authoritative (single source of truth)
- Ensures consistent conflict resolution
- Server can enforce complex business rules
- Client gets clear conflict response
- Can still allow client-side strategies for some conflicts

### Consequences
- Conflicts returned in push response
- Client must handle conflict response
- Multiple resolution strategies supported:
  - Server wins (default)
  - Last write wins
  - Field-level merge
- Client can retry with merged state

---

## TDR-007: JWT for Authentication

**Date:** 2024-01-15  
**Status:** ✅ Accepted  
**Deciders:** Core team

### Context
Choose authentication mechanism for sync server.

### Options Considered

1. **API Keys**
   - ✅ Simple
   - ❌ Must store secret
   - ❌ No expiration
   - ❌ Hard to revoke

2. **OAuth 2.0**
   - ✅ Standard
   - ✅ Scoped permissions
   - ❌ Complex setup
   - ❌ Requires auth provider

3. **JWT** (Chosen)
   - ✅ Stateless
   - ✅ Contains claims (user, device)
   - ✅ Expiration built-in
   - ✅ Standard (RFC 7519)
   - ❌ Requires token refresh

### Decision
Use **JWT (JSON Web Tokens)** for authentication.

### Rationale
- Stateless - server doesn't need session storage
- Contains user/device claims
- Built-in expiration
- Can be verified without DB lookup
- Standard across languages
- Integrates with existing auth systems

### Consequences
- Client must provide JWT in Authorization header
- Token refresh mechanism needed
- Server validates signature and expiration
- Can contain custom claims (device_id, db_id)

---

## TDR-008: HTTP/REST for Transport (Not WebSockets)

**Date:** 2024-01-15  
**Status:** ✅ Accepted  
**Deciders:** Core team

### Context
Choose transport protocol for sync operations.

### Options Considered

1. **WebSockets**
   - ✅ Real-time bidirectional
   - ✅ Lower latency
   - ❌ Complex error handling
   - ❌ Stateful connections
   - ❌ Harder to scale

2. **gRPC**
   - ✅ Efficient binary
   - ✅ Strong typing
   - ❌ Requires HTTP/2
   - ❌ Complex for web clients

3. **HTTP/REST** (Chosen)
   - ✅ Simple, well-understood
   - ✅ Stateless
   - ✅ Easy to debug/test
   - ✅ Works everywhere (firewall-friendly)
   - ✅ Easy to scale
   - ❌ Polling overhead

### Decision
Use **HTTP/REST** with CBOR payloads.

### Rationale
- Simpler implementation
- Stateless (easier to scale)
- Works in all environments
- Easy to debug (can use curl, Postman)
- Good enough for sync use case (not real-time chat)
- Can optimize with long polling or SSE later

### Consequences
- Three endpoints: /sync/handshake, /sync/pull, /sync/push
- CBOR request/response bodies
- Client polls at intervals
- Can add long-polling later for efficiency
- Easy to add CDN/load balancer

---

## TDR-009: Cursor-Based Pagination (Not Offset)

**Date:** 2024-01-15  
**Status:** ✅ Accepted  
**Deciders:** Core team

### Context
Choose pagination strategy for pulling operations from server.

### Options Considered

1. **Offset-Based**
   - ✅ Simple
   - ❌ Skips items if new ops inserted
   - ❌ Slow for large offsets

2. **Cursor-Based** (Chosen)
   - ✅ Stable across insertions
   - ✅ Efficient queries
   - ✅ Resumable sync
   - ❌ Slightly more complex

### Decision
Use **cursor-based pagination** with operation IDs.

### Rationale
- Operation IDs are monotonically increasing
- "Give me all operations > cursor" is efficient query
- Stable even as new operations added
- Enables resumable sync
- Client stores cursor locally

### Consequences
- Client maintains `SyncCursor` with last synced op ID
- Server returns operations > cursor
- No missed operations even with concurrent writes
- Client can resume sync after disconnect

---

## TDR-010: Dart SDK 3.10.1+ Required

**Date:** 2024-01-15  
**Status:** ✅ Accepted  
**Deciders:** Core team

### Context
EntiDB requires Dart 3.10.1+. Decide if entidb_sync should require same.

### Options Considered

1. **Lower Requirement (3.5+)**
   - ✅ Broader compatibility
   - ❌ Can't use EntiDB

2. **Match EntiDB (3.10.1+)** (Chosen)
   - ✅ No version conflicts
   - ✅ Can use latest Dart features
   - ❌ Some users may need to upgrade

### Decision
Require **Dart SDK ^3.10.1** to match EntiDB.

### Rationale
- EntiDB is core dependency
- Prevents version conflicts
- Allows using latest language features
- Upgrade path is straightforward
- Most developers on recent Dart versions

### Consequences
- Clear documentation of requirement
- Setup scripts check Dart version
- Upgrade instructions provided
- May need to help users upgrade

---

## Summary Table

| # | Decision | Status | Impact |
|---|----------|--------|--------|
| 001 | CBOR for wire protocol | ✅ | High |
| 002 | Oplog above WAL | ✅ | High |
| 003 | Monorepo structure | ✅ | Medium |
| 004 | Pull-then-push cycle | ✅ | High |
| 005 | Operation-based sync | ✅ | High |
| 006 | Server-side conflict resolution | ✅ | High |
| 007 | JWT authentication | ✅ | Medium |
| 008 | HTTP/REST transport | ✅ | High |
| 009 | Cursor-based pagination | ✅ | Medium |
| 010 | Dart 3.10.1+ requirement | ✅ | Low |

---

## Adding New TDRs

When making significant technical decisions:

1. Copy template below
2. Fill in all sections
3. Discuss with team
4. Update status when decided
5. Add to summary table

### Template

```markdown
## TDR-XXX: [Decision Title]

**Date:** YYYY-MM-DD  
**Status:** 🤔 Proposed / ✅ Accepted / ❌ Rejected / ♻️ Superseded  
**Deciders:** [Who decided]

### Context
[Why is this decision needed? What's the problem?]

### Options Considered

1. **Option A**
   - ✅ Pros
   - ❌ Cons

2. **Option B** (Chosen)
   - ✅ Pros
   - ❌ Cons

### Decision
[What was decided and why]

### Rationale
[Detailed reasoning]

### Consequences
[What follows from this decision]
```

---

*TDRs are living documents. As the project evolves, decisions may be revisited and superseded.*
