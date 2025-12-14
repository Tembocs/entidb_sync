Below is a **fully rewritten, consolidated, and unambiguous architectural document** that incorporates **all clarifications to date**, including:

* Explicit endpoint configuration (no discovery, no guessing)
* Explicit use of **Dart across client, sync, and server**
* Explicit statement that **the server runs its own EntiDB instance**
* Clear separation of concerns
* Concrete responsibilities, invariants, and flows
* Sufficient detail to implement without ambiguity

This is intended to be **authoritative**. You should be able to implement directly from it.

---

# EntiDB Synchronization Architecture

## Table of Contents

1. [Architectural Intent](#1-architectural-intent)
2. [Core Architectural Principle](#2-core-architectural-principle-non-negotiable)
3. [High-Level System Overview](#3-high-level-system-overview)
4. [Technology Choice: Dart Everywhere](#4-technology-choice-dart-everywhere)
5. [Explicit Endpoint Configuration](#5-explicit-endpoint-configuration-no-discovery)
6. [EntiDB Core: Sync-Aware but Not Sync-Dependent](#6-entidb-core-sync-aware-but-not-sync-dependent)
7. [EntiDB_Sync: Client-Side Synchronization Engine](#7-entidb_sync-client-side-synchronization-engine)
8. [Synchronization Model](#8-synchronization-model)
9. [Conflict Model](#9-conflict-model)
10. [Sync Protocol](#10-sync-protocol)
11. [Sync Server Architecture](#11-sync-server-architecture)
12. [Architectural Invariants](#12-architectural-invariants-must-hold-forever)
13. [Final Summary](#13-final-summary)
14. [Integration with EntiDB](#14-integration-with-entidb)
15. [Protocols](#protocols)

---

**Authoritative and Implementation-Grade Specification**

---

## 1. Architectural Intent

EntiDB is an **entity-based embedded database engine** written in Dart, designed to be:

* Local-first
* Embedded
* Deterministic
* Transactional
* Platform-agnostic (mobile, desktop, server)

Synchronization is an **optional capability**, added **without altering EntiDB’s embedded nature**.
### 1.1 Current State & Project Scope

> **Important Context:**
> - **EntiDB core** (https://github.com/Tembocs/entidb) is **fully operational**
> - Features CBOR serialization, WAL, transactions, encryption, and indexes
> - **This project** (`entidb_sync`) builds synchronization **on top** of the existing engine
> - We are creating a new capability, not modifying EntiDB core
This document defines how synchronization is achieved **between multiple EntiDB instances** using:

* A client-side sync engine (`EntiDB_Sync`)
* A server-side orchestration layer
* A shared, explicit, versioned sync protocol

---

## 2. Core Architectural Principle (Non-Negotiable)

> **EntiDB is the single database engine used everywhere — on clients and on the server.**

There is:

* No “cloud-only” database engine
* No fork of EntiDB
* No separate persistence layer on the server

The system consists of **multiple EntiDB instances**, coordinated through synchronization.

---

## 3. High-Level System Overview

```
┌──────────────────────────────────────────────────────────────┐
│ Client Application (Flutter / Dart)                           │
│                                                              │
│  ┌────────────────────────┐                                 │
│  │ EntiDB (Client)         │                                 │
│  │  - Entities             │                                 │
│  │  - Indexes              │                                 │
│  │  - Transactions         │                                 │
│  │  - WAL                  │                                 │
│  │  - Migrations           │                                 │
│  │                          │                                 │
│  │  (Optional) Change Feed │◄───────────────┐               │
│  └────────────────────────┘                │               │
│                                            │               │
│  ┌──────────────────────────────────┐      │               │
│  │ EntiDB_Sync (Client Library)      │      │               │
│  │  - Sync state machine             │──────┼── HTTPS       │
│  │  - Push / Pull logic              │      │               │
│  │  - Conflict handling              │      │               │
│  │  - Offline-first                  │      │               │
│  │  - Retry / backoff                │      │               │
│  └──────────────────────────────────┘      │               │
│                                            │               │
└────────────────────────────────────────────┼───────────────┘
                                             ▼
┌──────────────────────────────────────────────────────────────┐
│ Sync Server (Dart)                                            │
│                                                              │
│  ┌────────────────────────┐                                 │
│  │ EntiDB (Server)         │                                 │
│  │  - Authoritative data   │                                 │
│  │  - Server oplog         │                                 │
│  │  - Indexes              │                                 │
│  │  - Transactions         │                                 │
│  └────────────────────────┘                                 │
│                                                              │
│  ┌────────────────────────┐                                 │
│  │ Sync API Layer          │                                 │
│  │  - HTTPS endpoints      │                                 │
│  │  - Authentication      │                                 │
│  │  - Cursor management    │                                 │
│  │  - Conflict detection   │                                 │
│  └────────────────────────┘                                 │
│                                                              │
└──────────────────────────────────────────────────────────────┘
```

---

## 4. Technology Choice: Dart Everywhere

### 4.1 Deliberate Language Choice

This project **intentionally uses Dart across all layers**:

| Layer                   | Language |
| ----------------------- | -------- |
| EntiDB core             | Dart     |
| EntiDB_Sync client      | Dart     |
| Sync server (reference) | Dart     |

This is a **design decision**, not an accident.

### 4.2 Rationale

Using Dart everywhere provides:

* A single language and type system
* Shared data models (entities, ops, conflicts)
* Shared serialization (JSON / CBOR)
* Identical behavior across platforms
* Tight Flutter integration
* Simplified maintenance and testing

The **protocol is language-agnostic**, but the **reference implementation is Dart-first**.

### 4.3 Dependency Constraints (Non-Negotiable)

> **No dependencies that require code generation are permitted.**

This project explicitly prohibits:

* `build_runner` as a runtime or dev dependency for production code
* `freezed`, `json_serializable`, `built_value`, or similar code-gen packages
* Any package that requires `dart run build_runner build` to function

**Rationale:**

* Code generation adds complexity to the build process
* Generated code creates merge conflicts and maintenance burden
* Manual implementation ensures full control and understanding
* Reduces dependency surface and potential security issues

All models, serialization, and equality implementations must be **hand-written**.

### 4.4 Database Engine Exclusivity (Non-Negotiable)

> **EntiDB is the only database engine permitted in this project.**

There is:

* No SQLite, Hive, Isar, or ObjectBox
* No Firebase, Supabase, or cloud-specific databases
* No PostgreSQL, MySQL, or other external database engines
* No abstraction layers that support multiple database backends

**Rationale:**

* This project exists specifically to provide synchronization for EntiDB
* EntiDB runs on both client and server (architectural invariant from Section 2)
* Adding alternative databases would violate the core design principle
* The sync protocol is optimized for EntiDB's CBOR-native storage format

All persistence, both client-side and server-side, uses **EntiDB exclusively**.

---

## 5. Explicit Endpoint Configuration (No Discovery)

### 5.1 Absolute Rule

> **EntiDB_Sync never discovers servers.**

There is:

* No peer discovery
* No IP scanning
* No multicast / broadcast
* No inbound listening
* No “guessing”

All sync communication is:

* **Outbound**
* **HTTPS**
* **Explicitly configured**

---

### 5.2 Sync Configuration

The application **must provide** the server endpoint.

Illustrative example:

```dart
final sync = EntiDBSync(
  db: entidb,
  config: SyncConfig(
    serverUrl: Uri.parse("https://sync.example.org"),
    dbId: "production-db",
    deviceId: "android-a92f1",
    authTokenProvider: () async => getAuthToken(),
  ),
);
```

### 5.3 What the Client Knows

* A **URL** (not an IP, not a peer)
* A database identifier (`dbId`)
* A stable device identifier (`deviceId`)
* How to obtain an auth token

DNS resolution, routing, TLS are handled by the OS.

---

## 6. EntiDB Core: Sync-Aware but Not Sync-Dependent

### 6.1 Embedded Purity

EntiDB core:

* Has **no networking code**
* Has **no sync knowledge**
* Can be compiled and used without EntiDB_Sync

---

### 6.2 Change Feed / Operation Log (NEW - To Be Implemented)

> **Critical Distinction:** This is a **new capability** to be built on top of EntiDB's
> existing WAL infrastructure.
>
> - **EntiDB's WAL** provides crash recovery and transaction durability (physical log)
> - **Sync Oplog** will provide replication and synchronization (logical log)
> - The oplog observes WAL commits and transforms them into replication events

EntiDB will expose a **sync operation log**, disabled by default.

Purpose:

* Provide a deterministic stream of committed mutations
* Enable synchronization without modifying core logic
* Bridge the gap between physical WAL and logical replication

#### Integration with Existing EntiDB WAL

EntiDB already has:

* `WalWriter` - Logs transaction operations (insert, update, delete)
* `WalReader` - Reads WAL for recovery
* `DataOperationPayload` - CBOR-encoded mutation data

The sync oplog will:

* Observe WAL commit records
* Extract `DataOperationPayload` from committed transactions
* Transform physical WAL records into logical `SyncOperation` records
* Maintain separate cursor/sequence for replication

#### Operation Record (Conceptual)

```
DbOperation
-----------
opId          : int        // Monotonic, local
dbId          : string
deviceId      : string
collection    : string
entityId      : string
opType        : PUT | DELETE
payload       : Map<String, dynamic>?  // null for DELETE
entityVersion : int
timestampMs   : int        // informational only
```

#### Guarantees

* Emitted only on successful transaction commit
* Append-only
* Local-only
* Safe to compact
* Independent of WAL internals

---

## 7. EntiDB_Sync: Client-Side Synchronization Engine

### 7.1 Definition

**EntiDB_Sync is a client-side library.**

It:

* Runs inside the application process
* Observes EntiDB
* Sends outbound HTTPS requests
* Never accepts inbound connections

It is **not a server**.

---

### 7.2 Responsibilities

EntiDB_Sync is responsible for:

* Subscribing to EntiDB change feed
* Tracking local oplog progress
* Persisting sync state (cursors, deviceId)
* Pulling remote changes
* Pushing local changes
* Applying remote changes transactionally
* Detecting and surfacing conflicts
* Supporting offline-first operation

---

## 8. Synchronization Model

### 8.1 Model Choice

The system uses a **pull-then-push** model.

Reasons:

* Offline-friendly
* Deterministic
* Simple to reason about
* No distributed locking
* No real-time coupling required

---

### 8.2 Sync Cycle

1. **Pull**

   * Client requests server changes since last known server cursor
   * Server responds with ordered operations
   * Client applies them in a single EntiDB transaction
   * Server cursor is advanced locally

2. **Conflict Detection**

   * Server detects conflicts during push
   * Conflicts are returned explicitly

3. **Push**

   * Client sends local operations not yet acknowledged
   * Server validates and applies them transactionally
   * Server emits new authoritative operations

4. **Compaction**

   * Client may compact local oplog up to acknowledged opId

---

## 9. Conflict Model

### 9.1 Authority

The **server-side EntiDB instance is authoritative by policy**, not by engine design.

### 9.2 Conflict Detection

A conflict occurs when:

* A client mutation is based on an outdated server revision
* Another client has already committed a concurrent mutation

### 9.3 Conflict Resolution

Resolution is **pluggable** and application-defined.

```dart
abstract class ConflictResolver {
  Future<Resolution> resolve({
    required SyncOperation clientOp,
    required ServerState serverState,
  });
}

enum ResolutionType {
  acceptClient,    // Apply client change, broadcast to others
  rejectClient,    // Keep server state, force client update
  merge,          // Custom merge logic applied
}

class Resolution {
  final ResolutionType type;
  final Map<String, dynamic>? mergedData;
  
  Resolution.acceptClient() : type = ResolutionType.acceptClient, mergedData = null;
  Resolution.rejectClient() : type = ResolutionType.rejectClient, mergedData = null;
  Resolution.merge(this.mergedData) : type = ResolutionType.merge;
}

class ServerState {
  final int entityVersion;
  final Map<String, dynamic> currentData;
  final DateTime lastModified;
}
```

EntiDB core **never resolves conflicts**.

### 9.4 Built-in Resolution Strategies

#### Server Wins (Default)
```dart
class ServerWinsResolver implements ConflictResolver {
  @override
  Future<Resolution> resolve({
    required SyncOperation clientOp,
    required ServerState serverState,
  }) async {
    // Always reject client changes when conflict detected
    return Resolution.rejectClient();
  }
}
```

#### Last-Write-Wins (Timestamp-based)
```dart
class LastWriteWinsResolver implements ConflictResolver {
  @override
  Future<Resolution> resolve({
    required SyncOperation clientOp,
    required ServerState serverState,
  }) async {
    if (clientOp.timestampMs > serverState.lastModified.millisecondsSinceEpoch) {
      return Resolution.acceptClient();
    } else {
      return Resolution.rejectClient();
    }
  }
}
```

#### Custom Field-Level Merge
```dart
class FieldMergeResolver implements ConflictResolver {
  @override
  Future<Resolution> resolve({
    required SyncOperation clientOp,
    required ServerState serverState,
  }) async {
    // Merge non-conflicting fields
    final merged = Map<String, dynamic>.from(serverState.currentData);
    
    clientOp.payload?.forEach((key, value) {
      if (!serverState.currentData.containsKey(key) || 
          serverState.currentData[key] == value) {
        merged[key] = value;
      }
    });
    
    return Resolution.merge(merged);
  }
}
```

---

## 10. Sync Protocol

### 10.1 Transport

* HTTPS
* HTTP/1.1 or HTTP/2
* JSON by default
* Optional CBOR encoding

### 10.2 Authentication

* Bearer token via `Authorization` header
* Token acquisition is application-defined

---

### 10.3 Endpoints (v1)

| Endpoint             | Purpose               |
| -------------------- | --------------------- |
| `POST /v1/handshake` | Capability exchange   |
| `POST /v1/pull`      | Fetch server changes  |
| `POST /v1/push`      | Submit client changes |
| `GET /v1/stream`     | Optional SSE updates  |

---

## 11. Sync Server Architecture

### 11.1 Definition

The sync server is:

* A Dart application
* Hosting an EntiDB instance
* Exposing HTTPS APIs
* Acting as synchronization coordinator

---

### 11.2 Server Responsibilities

* Authenticate clients
* Maintain authoritative EntiDB state
* Persist server-side change log
* Detect conflicts
* Assign ordered cursors
* Enforce policies

---

### 11.3 What the Server Is Not

* Not a database engine replacement
* Not peer-to-peer
* Not embedded
* Not language-specific (protocol-wise)

---

## 12. Architectural Invariants (Must Hold Forever)

1. EntiDB is used identically on client and server
2. Sync is optional and explicitly configured
3. No client performs inbound networking
4. All sync traffic is outbound HTTPS
5. Server authority is a policy choice
6. Sync failures never corrupt local state
7. Offline operation is first-class

---

## 13. Final Summary

* EntiDB is the **single database engine everywhere**
* EntiDB_Sync is a **deterministic, explicit client-side sync layer**
* The server runs **its own EntiDB instance**
* Synchronization coordinates EntiDB instances — it does not replace them
* Dart is deliberately used across all layers
* No discovery, no ambiguity, no hidden behavior

This architecture is **robust, implementable, and future-proof**.

---

## 14. Integration with EntiDB

### 14.1 EntiDB Capabilities (Already Available)

EntiDB provides all necessary primitives for synchronization:

| EntiDB Capability | Location | Sync Usage |
|-------------------|----------|------------|
| **WAL** | `lib/src/engine/wal/` | Source for sync oplog observation |
| **CBOR Serialization** | `BinarySerializer` | Direct entity encoding for transport |
| **Entity Versioning** | Collection-level | Conflict detection input |
| **Transactions** | `TransactionManager` | Atomic sync operation application |
| **Encryption** | `AesGcmEncryptionService` | Optional end-to-end encryption |
| **Storage Abstraction** | `Storage<T>` interface | Server-side persistence |

### 14.2 WAL Structure (Existing)

```dart
// From entidb: lib/src/engine/wal/wal_record.dart
class DataOperationPayload {
  final String collectionName;
  final String entityId;
  final Map<String, dynamic>? beforeImage;
  final Map<String, dynamic>? afterImage;
  
  Uint8List toBytes() { /* CBOR encoding */ }
  factory DataOperationPayload.fromBytes(Uint8List bytes) { /* CBOR decoding */ }
}

enum WalRecordType {
  beginTransaction,
  commitTransaction,
  abortTransaction,
  insert,
  update,
  delete,
  checkpoint,
}
```

### 14.3 New Components Required

**In `entidb_sync_client`:**
- `SyncOplogService` - Observes WAL, emits `SyncOperation` records
- `SyncClient` - HTTPS transport, cursor management, retry logic
- `OfflineQueue` - Persists pending operations during disconnection
- `ConflictHandler` - Surfaces conflicts to application

**In `entidb_sync_server`:**
- `SyncEndpoints` - HTTP handlers for handshake/pull/push
- `ServerOplogManager` - Server-side operation log with global ordering
- `ConflictDetector` - Compares client ops against server state
- `CursorManager` - Tracks per-client sync progress

**In `entidb_sync_protocol`:**
- `SyncOperation` - Logical replication record (CBOR codecs)
- `Conflict` - Conflict representation with resolution context
- `SyncConfig` - Client configuration model

### 14.4 Data Flow

```
Client App
    │
    ├─ EntiDB (local)
    │   └─ WAL (physical log)
    │       └─ DataOperationPayload (CBOR)
    │
    ├─ SyncOplogService
    │   └─ observes WAL commits
    │   └─ transforms to SyncOperation (logical log)
    │
    └─ SyncClient
        └─ HTTPS ───────────────► Server
                                    │
                                    ├─ SyncEndpoints
                                    │   └─ parse CBOR requests
                                    │
                                    ├─ EntiDB (server)
                                    │   └─ authoritative state
                                    │
                                    └─ ServerOplogManager
                                        └─ emit ordered ops to clients
```

### 14.5 Implementation Notes

1. **WAL Observation:** Use `WalReader.forEach()` to consume commit records
2. **CBOR Reuse:** Wrap `DataOperationPayload` bytes directly, no re-encoding
3. **Entity Blobs:** EntiDB already stores entities as CBOR via `BinarySerializer`
4. **Versioning:** Collections track entity versions via internal metadata
5. **Isolation:** Sync logic never touches EntiDB core, only observes and applies

---


Below is the **updated version of the first four deliverables**, revised to **explicitly incorporate CBOR-native transmission**, clarify **why a protocol still exists**, and remove any ambiguity between **encoding vs semantics**.

I have **not** included item 5, per your instruction.

This replaces the earlier versions of Deliverables **1–4** and should be treated as **authoritative** going forward.

---

# Protocals

## SyncProtocol v1 — Formal Specification (CBOR-Native)

**Status:** Draft v1 (implementation-ready)
**Transport:** HTTPS (mandatory)
**Encoding:** **CBOR (primary, canonical)**
**Direction:** Client → Server (outbound only)
**Database Engine (Both Sides):** EntiDB
**Authority:** Server-side EntiDB instance (by policy)

---

## 1. Protocol vs Encoding (Normative Clarification)

### 1.1 Definitions

* **Protocol** defines:

  * Meaning of messages
  * Ordering guarantees
  * Identity rules
  * Conflict semantics
  * Cursor progression
* **Encoding** defines:

  * How objects are serialized into bytes

**CBOR is the encoding.
SyncProtocol v1 defines the semantics.**

This protocol is **CBOR-native**. JSON examples are illustrative only.

---

## 2. Identity Model (Unchanged, Explicit)

| Identifier     | Scope      | Purpose                     |
| -------------- | ---------- | --------------------------- |
| `dbId`         | Global     | Logical database identity   |
| `deviceId`     | Per client | Stable device identity      |
| `opId`         | Per device | Monotonic local ordering    |
| `serverCursor` | Global     | Server-assigned total order |

No wall clocks are used for correctness.

---

## 3. Operation Model (CBOR-Wrapped EntiDB Objects)

### 3.1 Fundamental Rule

> **Entity payloads are transmitted as raw EntiDB CBOR bytes.
> Protocol metadata wraps them.**

The protocol never re-serializes entity objects into JSON-like structures.

---

### 3.2 Canonical Sync Operation Structure

Logical structure (language-neutral):

```
SyncOperation
-------------
opId            : int
dbId            : string
deviceId        : string
collection      : string
entityId        : string
opType          : PUT | DELETE
entityVersion   : int
entityCbor      : bytes | null
timestampMs     : int (informational only)
```

Encoding:

* The entire structure is encoded as **CBOR**
* `entityCbor` is a **raw CBOR blob produced by EntiDB**
* No interpretation of `entityCbor` is required by the protocol layer

---

### 3.3 Idempotency Rules

The server **must** deduplicate operations by:

```
(dbId, deviceId, opId)
```

Re-submission of the same operation must be safe.

---

## 4. Endpoints (Semantics Preserved, Encoding Changed)

All endpoints:

* Accept `Content-Type: application/cbor`
* Return `Content-Type: application/cbor`
* Are HTTPS only

---

### 4.1 Handshake

**POST** `/v1/handshake`

CBOR map:

```
{
  "dbId": string,
  "deviceId": string,
  "clientInfo": {
    "platform": string,
    "appVersion": string
  }
}
```

Response:

```
{
  "serverCursor": int,
  "capabilities": {
    "pull": bool,
    "push": bool,
    "sse": bool
  }
}
```

Purpose:

* Validate identity
* Initialize cursors
* Capability negotiation

---

### 4.2 Pull

**POST** `/v1/pull`

Request:

```
{
  "dbId": string,
  "sinceCursor": int,
  "limit": int
}
```

Response:

```
{
  "ops": [ SyncOperation ... ],
  "nextCursor": int,
  "hasMore": bool
}
```

Guarantees:

* Operations are ordered by `serverCursor`
* Idempotent
* Stateless

---

### 4.3 Push

**POST** `/v1/push`

Request:

```
{
  "dbId": string,
  "deviceId": string,
  "ops": [ SyncOperation ... ]
}
```

Response:

```
{
  "acknowledgedUpToOpId": int,
  "conflicts": [ Conflict ... ]
}
```

---

### 4.4 Conflict Object (CBOR)

```
Conflict
--------
collection
entityId
clientOp      : SyncOperation
serverState   : {
  entityVersion
  entityCbor
}
```

No automatic resolution unless explicitly configured.

---


## Reference Sync Server — Dart Architecture (Updated)

### 2.1 Core Principle

> **The server runs a full EntiDB instance.
> Sync coordinates EntiDB instances; it does not replace them.**

The server:

* Stores authoritative data in EntiDB
* Uses EntiDB transactions
* Emits a server-side oplog
* Wraps EntiDB with HTTPS APIs

---

### 2.2 Project Structure (Unchanged)

```
entidb_sync_server/
├─ bin/
│  └─ server.dart
├─ lib/
│  ├─ api/
│  ├─ auth/
│  ├─ sync/
│  └─ db/
└─ pubspec.yaml
```

---

### 2.3 CBOR Handling on Server

* Incoming request bodies are decoded as CBOR
* `entityCbor` blobs are passed **directly** into EntiDB
* No JSON conversion
* No schema re-interpretation

This guarantees **lossless round-tripping** of entities.

---


## Server-Side EntiDB Schema (Clarified for CBOR)

All payload fields store **CBOR blobs**, not structured JSON.

---

### 3.1 `entities`

```
entities
--------
collection        string
entityId          string
entityVersion     int
entityCbor        bytes   // raw EntiDB CBOR
deleted           bool
updatedByDevice   string
```

Indexes:

* `(collection, entityId)` UNIQUE

---

### 3.2 `server_oplog`

```
server_oplog
------------
serverCursor      int (monotonic)
dbId              string
collection        string
entityId          string
opType            PUT | DELETE
entityCbor        bytes | null
sourceDeviceId    string
sourceOpId        int
```

Indexes:

* `(dbId, serverCursor)`
* `(dbId, sourceDeviceId, sourceOpId)` UNIQUE

---

### 3.3 `device_state`

```
device_state
------------
dbId
deviceId
lastSeenCursor
lastSeenAt
```

---

### 3.4 `conflicts` (optional persistence)

```
conflicts
---------
dbId
collection
entityId
clientOpCbor
serverEntityCbor
detectedAt
```

---


## Sequence Diagrams (CBOR-Native Semantics)

---

## 4.1 Normal Sync (No Conflict)

```
Client (EntiDB)        Server (EntiDB)
     |                      |
     |-- handshake (CBOR) ->|
     |<- cursor (CBOR) -----|
     |                      |
     |-- pull (CBOR) ------>|
     |<- ops (CBOR) --------|
     | apply ops locally    |
     |                      |
     |-- push (CBOR) ------>|
     | server tx commit     |
     | append server oplog  |
     |<- ack (CBOR) --------|
```

---

## 4.2 Conflict Detection

```
Client A           Server           Client B
   |                 |                |
   |-- push v7 ----->|                |
   |                 | commit v8      |
   |                 |                |
   |                 |<-- push v7 ----|
   |                 | conflict       |
   |<-- conflict ----|                |
```

No silent overwrite occurs.

---

## 4.3 Offline Catch-Up

```
Client (offline)
   |
   | local ops recorded (CBOR)
   |
   | reconnect
   |
   |-- pull ---------->|
   |<- many ops -------|
   |-- push ---------->|
   |<- ack ------------|
```

---

# Final Consolidated Principle (Updated)

> **EntiDB objects remain CBOR end-to-end.
> SyncProtocol v1 defines meaning, not encoding.
> The protocol wraps raw EntiDB CBOR without reinterpretation.**

This design:

* Preserves EntiDB’s object model
* Avoids double serialization
* Keeps sync deterministic and debuggable
* Allows evolution without breaking data
