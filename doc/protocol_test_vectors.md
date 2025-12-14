# EntiDB Sync Protocol - Test Vectors

This document provides concrete CBOR examples for all sync protocol messages.

**Version:** 1.0  
**Encoding:** CBOR (RFC 8949)  
**Transport:** HTTPS with `Content-Type: application/cbor`

---

## Table of Contents

1. [Handshake](#1-handshake)
2. [Pull Request](#2-pull-request)
3. [Pull Response](#3-pull-response)
4. [Push Request](#4-push-request)
5. [Push Response](#5-push-response)
6. [Conflict Object](#6-conflict-object)
7. [SyncOperation](#7-syncoperation)
8. [CBOR Diagnostic Notation](#8-cbor-diagnostic-notation)

---

## 1. Handshake

### Request: POST /v1/handshake

**CBOR Diagnostic Notation:**
```
{
  "dbId": "production-db",
  "deviceId": "android-a92f1",
  "clientInfo": {
    "platform": "android",
    "appVersion": "1.2.3"
  }
}
```

**CBOR Hex:**
```
A3                              # map(3)
   64                           # text(4)
      64624964                  # "dbId"
   6D                           # text(13)
      70726F64756374696F6E2D6462 # "production-db"
   68                           # text(8)
      6465766963654964          # "deviceId"
   6E                           # text(14)
      616E64726F69642D61393266 31 # "android-a92f1"
   6A                           # text(10)
      636C69656E74496E666F      # "clientInfo"
   A2                           # map(2)
      68                        # text(8)
         706C6174666F726D       # "platform"
      67                        # text(7)
         616E64726F6964          # "android"
      6A                        # text(10)
         61707056657273696F6E   # "appVersion"
      65                        # text(5)
         312E322E33             # "1.2.3"
```

**Size:** 78 bytes

### Response: 200 OK

**CBOR Diagnostic Notation:**
```
{
  "serverCursor": 12345,
  "capabilities": {
    "pull": true,
    "push": true,
    "sse": false
  }
}
```

**CBOR Hex:**
```
A2                              # map(2)
   6C                           # text(12)
      73657276657243757273 6F72 # "serverCursor"
   19 3039                      # unsigned(12345)
   6C                           # text(12)
      63617061 62696C69746965 73 # "capabilities"
   A3                           # map(3)
      64                        # text(4)
         70756C6C               # "pull"
      F5                        # primitive(21) true
      64                        # text(4)
         70757368               # "push"
      F5                        # primitive(21) true
      63                        # text(3)
         737365                 # "sse"
      F4                        # primitive(20) false
```

**Size:** 52 bytes

---

## 2. Pull Request

### Request: POST /v1/pull

**CBOR Diagnostic Notation:**
```
{
  "dbId": "production-db",
  "sinceCursor": 12000,
  "limit": 100
}
```

**CBOR Hex:**
```
A3                              # map(3)
   64                           # text(4)
      64624964                  # "dbId"
   6D                           # text(13)
      70726F64756374696F6E2D6462 # "production-db"
   6B                           # text(11)
      73696E636543757273 6F72   # "sinceCursor"
   19 2EE0                      # unsigned(12000)
   65                           # text(5)
      6C696D6974                # "limit"
   18 64                        # unsigned(100)
```

**Size:** 41 bytes

---

## 3. Pull Response

### Response: 200 OK

**CBOR Diagnostic Notation:**
```
{
  "ops": [
    {
      "opId": 1001,
      "dbId": "production-db",
      "deviceId": "ios-device-7",
      "collection": "tasks",
      "entityId": "task-42",
      "opType": "PUT",
      "entityVersion": 3,
      "entityCbor": h'A26474697 46C65695461736B2031', // CBOR: {"title": "Task 1"}
      "timestampMs": 1702569600000
    }
  ],
  "nextCursor": 12346,
  "hasMore": false
}
```

**CBOR Hex (simplified, entityCbor shown as placeholder):**
```
A3                              # map(3)
   63 6F7073                    # text(3) "ops"
   81                           # array(1)
      A9                        # map(9)
         64 6F704964             # text(4) "opId"
         19 03E9                 # unsigned(1001)
         64 64624964             # text(4) "dbId"
         6D 70726F64756374696F6E2D6462 # text(13) "production-db"
         68 6465766963654964    # text(8) "deviceId"
         6D 696F732D6465766963652D37 # text(13) "ios-device-7"
         6A 636F6C6C656374696F6E # text(10) "collection"
         65 7461736B73           # text(5) "tasks"
         68 656E7469747949 64   # text(8) "entityId"
         67 7461736B2D3432       # text(7) "task-42"
         66 6F7054797065         # text(6) "opType"
         63 505554               # text(3) "PUT"
         6D 656E7469747956657273696F6E # text(13) "entityVersion"
         03                      # unsigned(3)
         6A 656E74697479436 26F72 # text(10) "entityCbor"
         4F A2647469746C 656... # bytes(15) [CBOR blob]
         6B 74696D657374 616D704D73 # text(11) "timestampMs"
         1B 0000018C7E5F4000    # unsigned(1702569600000)
   6A 6E65787443757273 6F72    # text(10) "nextCursor"
   19 303A                      # unsigned(12346)
   67 6861734D6F7265            # text(7) "hasMore"
   F4                           # primitive(20) false
```

**Size:** ~180 bytes (varies with entityCbor content)

---

## 4. Push Request

### Request: POST /v1/push

**CBOR Diagnostic Notation:**
```
{
  "dbId": "production-db",
  "deviceId": "android-a92f1",
  "ops": [
    {
      "opId": 5001,
      "dbId": "production-db",
      "deviceId": "android-a92f1",
      "collection": "notes",
      "entityId": "note-99",
      "opType": "PUT",
      "entityVersion": 1,
      "entityCbor": h'A26374657874656E6577206E6F7465', // {"text": "new note"}
      "timestampMs": 1702569610000
    }
  ]
}
```

**CBOR Hex (simplified):**
```
A3                              # map(3)
   64 64624964                  # text(4) "dbId"
   6D 70726F64756374696F6E2D6462 # text(13) "production-db"
   68 6465766963654964          # text(8) "deviceId"
   6E 616E64726F69642D61393266 31 # text(14) "android-a92f1"
   63 6F7073                    # text(3) "ops"
   81                           # array(1)
      A9                        # map(9)
         # ... [similar structure to pull response] ...
```

**Size:** ~190 bytes

---

## 5. Push Response

### Response: 200 OK (No conflicts)

**CBOR Diagnostic Notation:**
```
{
  "acknowledgedUpToOpId": 5001,
  "conflicts": []
}
```

**CBOR Hex:**
```
A2                              # map(2)
   75 61636B6E6F776C65646765645570546F4F704964 # text(21) "acknowledgedUpToOpId"
   19 1389                      # unsigned(5001)
   69 636F6E666C69637473        # text(9) "conflicts"
   80                           # array(0)
```

**Size:** 34 bytes

### Response: 200 OK (With conflict)

**CBOR Diagnostic Notation:**
```
{
  "acknowledgedUpToOpId": 5000,
  "conflicts": [
    {
      "collection": "notes",
      "entityId": "note-99",
      "clientOp": {
        "opId": 5001,
        "entityVersion": 1,
        "entityCbor": h'...'
      },
      "serverState": {
        "entityVersion": 2,
        "entityCbor": h'...'
      }
    }
  ]
}
```

**Size:** ~250 bytes (varies with entity size)

---

## 6. Conflict Object

**CBOR Diagnostic Notation:**
```
{
  "collection": "tasks",
  "entityId": "task-42",
  "clientOp": {
    "opId": 1234,
    "dbId": "production-db",
    "deviceId": "android-a92f1",
    "collection": "tasks",
    "entityId": "task-42",
    "opType": "PUT",
    "entityVersion": 5,
    "entityCbor": h'A2647469746C656B436C69656E742076696577',
    "timestampMs": 1702569615000
  },
  "serverState": {
    "entityVersion": 6,
    "entityCbor": h'A2647469746C656B53657276657220766965 77'
  }
}
```

---

## 7. SyncOperation

**Complete Example:**

**CBOR Diagnostic Notation:**
```
{
  "opId": 42,
  "dbId": "production-db",
  "deviceId": "web-client-abc",
  "collection": "products",
  "entityId": "prod-1001",
  "opType": "PUT",
  "entityVersion": 7,
  "entityCbor": h'A3646E616D 65694D7920507 26F6475637465707269636 518 64657461696C73A16 3736B7565224445544149 4C5322',
  "timestampMs": 1702569620000
}
```

**Decoded entityCbor:**
```dart
{
  "name": "My Product",
  "price": 100,
  "details": {"sku": "DETAILS"}
}
```

**Full CBOR Hex:**
```
A9                              # map(9)
   64 6F704964                  # text(4) "opId"
   18 2A                        # unsigned(42)
   64 64624964                  # text(4) "dbId"
   6D 70726F64756374696F6E2D6462 # text(13) "production-db"
   68 6465766963654964          # text(8) "deviceId"
   6E 7765622D636C69656E742D616263 # text(14) "web-client-abc"
   6A 636F6C6C656374696F6E      # text(10) "collection"
   68 70726F6475637473          # text(8) "products"
   68 656E7469747949 64         # text(8) "entityId"
   69 70726F642D31303031        # text(9) "prod-1001"
   66 6F7054797065              # text(6) "opType"
   63 505554                    # text(3) "PUT"
   6D 656E7469747956657273696F6E # text(13) "entityVersion"
   07                           # unsigned(7)
   6A 656E74697479436 26F72     # text(10) "entityCbor"
   58 35                        # bytes(53)
      A3646E616D 65694D7920...  # [53 bytes of CBOR]
   6B 74696D657374 616D704D73   # text(11) "timestampMs"
   1B 0000018C7E5F7920          # unsigned(1702569620000)
```

**Size:** ~170 bytes

---

## 8. CBOR Diagnostic Notation

All examples use [CBOR Diagnostic Notation](https://www.rfc-editor.org/rfc/rfc8949.html#name-diagnostic-notation) for readability.

### Key Conventions:

- `A3` = map with 3 entries
- `81` = array with 1 element
- `h'...'` = byte string (hex notation)
- `F5` = true
- `F4` = false
- `19 3039` = unsigned integer 12345
- `1B ...` = 64-bit unsigned integer

### Tools for CBOR:

**Encoding/Decoding:**
```dart
import 'package:cbor/cbor.dart';

// Encode
final cborBytes = cbor.encode(CborMap({
  CborString('dbId'): CborString('production-db'),
  CborString('sinceCursor'): CborInt(BigInt.from(12000)),
}));

// Decode
final cborValue = cbor.decode(cborBytes);
```

**Hex Dump:**
```bash
# Using cbor-diag tool
echo 'A264646249646D70726F64756374696F6E2D6462' | xxd -r -p | cbor-diag
```

---

## Testing

Use these test vectors to validate:

1. **Encoding Correctness:** Serialize objects and compare hex output
2. **Decoding Correctness:** Parse hex and verify resulting objects
3. **Round-trip Consistency:** Encode → Decode → Encode should match
4. **Size Validation:** Verify actual sizes match documented sizes

### Example Test:

```dart
import 'package:test/test.dart';
import 'package:entidb_sync_protocol/entidb_sync_protocol.dart';

void main() {
  test('Handshake request encoding', () {
    final request = HandshakeRequest(
      dbId: 'production-db',
      deviceId: 'android-a92f1',
      clientInfo: {
        'platform': 'android',
        'appVersion': '1.2.3',
      },
    );
    
    final bytes = request.toBytes();
    expect(bytes.length, equals(78)); // Size from test vector
    
    // Verify can be decoded
    final decoded = HandshakeRequest.fromBytes(bytes);
    expect(decoded.dbId, equals('production-db'));
  });
}
```

---

**Document Version:** 1.0  
**Last Updated:** December 14, 2025  
**Maintained By:** EntiDB Sync Team
