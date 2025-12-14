/// EntiDB Sync Protocol
///
/// Shared protocol definitions and CBOR codecs for EntiDB synchronization.
///
/// This package contains:
/// - Data models: SyncOperation, Conflict, Cursor, SyncConfig
/// - Protocol messages: Handshake, Pull, Push requests/responses
/// - CBOR encoders/decoders for efficient wire protocol
/// - Protocol versioning and compatibility checks
///
/// This is a pure protocol package with no side effects or I/O operations.
library entidb_sync_protocol;

// Models
export 'src/models/sync_operation.dart';
export 'src/models/conflict.dart';
export 'src/models/cursor.dart';
export 'src/models/sync_config.dart';

// Protocol messages
export 'src/messages/messages.dart';

// CBOR encoding/decoding
export 'src/cbor/encoders.dart';
export 'src/cbor/decoders.dart';

// Protocol versioning
export 'src/protocol_version.dart';
