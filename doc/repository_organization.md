# Repository Structure

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
entidb_sync  (repository)
├─ packages/
│  ├─ entidb_sync_client   ← used by apps
│  ├─ entidb_sync_server   ← deployable service
│  └─ entidb_sync_protocol ← shared CBOR/protocol models
```

This is **one repository**, multiple clearly scoped deliverables.

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
