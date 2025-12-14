/// Cursor Model
///
/// Tracks synchronization progress for resumable sync.
library;

import 'package:meta/meta.dart';

/// Sync cursor for tracking progress.
///
/// Cursors enable resumable sync by tracking which operations have been
/// synchronized. Both client and server maintain cursors.
@immutable
class SyncCursor {
  /// Last synchronized operation ID.
  final int lastOpId;

  /// Server cursor position (for pull operations).
  final int serverCursor;

  /// Timestamp of last successful sync.
  final DateTime lastSyncAt;

  const SyncCursor({
    required this.lastOpId,
    required this.serverCursor,
    required this.lastSyncAt,
  });

  /// Creates an initial cursor (no sync yet).
  factory SyncCursor.initial() {
    return SyncCursor(
      lastOpId: 0,
      serverCursor: 0,
      lastSyncAt: DateTime.fromMillisecondsSinceEpoch(0),
    );
  }

  /// Creates a copy with updated values.
  SyncCursor copyWith({
    int? lastOpId,
    int? serverCursor,
    DateTime? lastSyncAt,
  }) {
    return SyncCursor(
      lastOpId: lastOpId ?? this.lastOpId,
      serverCursor: serverCursor ?? this.serverCursor,
      lastSyncAt: lastSyncAt ?? this.lastSyncAt,
    );
  }

  /// Serializes to JSON.
  Map<String, dynamic> toJson() => {
        'lastOpId': lastOpId,
        'serverCursor': serverCursor,
        'lastSyncAt': lastSyncAt.toIso8601String(),
      };

  /// Deserializes from JSON.
  factory SyncCursor.fromJson(Map<String, dynamic> json) {
    return SyncCursor(
      lastOpId: json['lastOpId'] as int,
      serverCursor: json['serverCursor'] as int,
      lastSyncAt: DateTime.parse(json['lastSyncAt'] as String),
    );
  }

  @override
  String toString() => 'SyncCursor('
      'lastOpId: $lastOpId, '
      'serverCursor: $serverCursor, '
      'lastSyncAt: $lastSyncAt'
      ')';
}
