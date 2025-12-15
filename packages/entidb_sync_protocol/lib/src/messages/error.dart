/// Error Response Messages
///
/// Protocol messages for error handling in sync operations.
library;

import 'dart:typed_data';

import 'package:meta/meta.dart';

import '../cbor/decoders.dart';
import '../cbor/encoders.dart';

/// Error codes for sync protocol errors.
enum SyncErrorCode {
  /// Unknown or unspecified error.
  unknown(0),

  /// Invalid request format or missing required fields.
  invalidRequest(1),

  /// Authentication failed or token expired.
  authenticationFailed(2),

  /// Client not authorized to access resource.
  authorizationFailed(3),

  /// Database not found.
  databaseNotFound(4),

  /// Protocol version mismatch.
  versionMismatch(5),

  /// Conflict detected during push.
  conflict(6),

  /// Rate limit exceeded.
  rateLimitExceeded(7),

  /// Server internal error.
  internalError(8),

  /// Service temporarily unavailable.
  serviceUnavailable(9),

  /// Request timeout.
  timeout(10),

  /// Invalid cursor position.
  invalidCursor(11),

  /// Operation not supported.
  notSupported(12);

  /// The numeric value for this error code.
  final int value;

  const SyncErrorCode(this.value);

  /// Creates a [SyncErrorCode] from its numeric value.
  static SyncErrorCode fromValue(int value) {
    return switch (value) {
      0 => SyncErrorCode.unknown,
      1 => SyncErrorCode.invalidRequest,
      2 => SyncErrorCode.authenticationFailed,
      3 => SyncErrorCode.authorizationFailed,
      4 => SyncErrorCode.databaseNotFound,
      5 => SyncErrorCode.versionMismatch,
      6 => SyncErrorCode.conflict,
      7 => SyncErrorCode.rateLimitExceeded,
      8 => SyncErrorCode.internalError,
      9 => SyncErrorCode.serviceUnavailable,
      10 => SyncErrorCode.timeout,
      11 => SyncErrorCode.invalidCursor,
      12 => SyncErrorCode.notSupported,
      _ => SyncErrorCode.unknown,
    };
  }
}

/// Error response from the sync server.
///
/// Returned when a sync operation fails. Contains structured error
/// information for client-side handling.
@immutable
class ErrorResponse {
  /// Creates an error response.
  const ErrorResponse({
    required this.code,
    required this.message,
    this.details,
    this.field,
    this.retryAfterSeconds,
    this.requestId,
  });

  /// Creates an invalid request error.
  factory ErrorResponse.invalidRequest(String message, {String? field}) {
    return ErrorResponse(
      code: SyncErrorCode.invalidRequest,
      message: message,
      field: field,
    );
  }

  /// Creates an authentication error.
  factory ErrorResponse.authenticationFailed({String? message}) {
    return ErrorResponse(
      code: SyncErrorCode.authenticationFailed,
      message: message ?? 'Authentication failed',
    );
  }

  /// Creates an authorization error.
  factory ErrorResponse.authorizationFailed({String? message}) {
    return ErrorResponse(
      code: SyncErrorCode.authorizationFailed,
      message: message ?? 'Not authorized to access this resource',
    );
  }

  /// Creates a database not found error.
  factory ErrorResponse.databaseNotFound(String dbId) {
    return ErrorResponse(
      code: SyncErrorCode.databaseNotFound,
      message: 'Database not found: $dbId',
    );
  }

  /// Creates a version mismatch error.
  factory ErrorResponse.versionMismatch({
    required int clientVersion,
    required int serverVersion,
    required int minSupported,
  }) {
    return ErrorResponse(
      code: SyncErrorCode.versionMismatch,
      message: 'Protocol version mismatch',
      details:
          'Client: $clientVersion, Server: $serverVersion, '
          'Min supported: $minSupported',
    );
  }

  /// Creates a conflict error.
  factory ErrorResponse.conflict(String message, {String? details}) {
    return ErrorResponse(
      code: SyncErrorCode.conflict,
      message: message,
      details: details,
    );
  }

  /// Creates a rate limit error.
  factory ErrorResponse.rateLimitExceeded({
    required int retryAfterSeconds,
    String? message,
  }) {
    return ErrorResponse(
      code: SyncErrorCode.rateLimitExceeded,
      message: message ?? 'Rate limit exceeded',
      retryAfterSeconds: retryAfterSeconds,
    );
  }

  /// Creates an internal error.
  factory ErrorResponse.internalError({String? message, String? requestId}) {
    return ErrorResponse(
      code: SyncErrorCode.internalError,
      message: message ?? 'Internal server error',
      requestId: requestId,
    );
  }

  /// Creates a service unavailable error.
  factory ErrorResponse.serviceUnavailable({
    String? message,
    int? retryAfterSeconds,
  }) {
    return ErrorResponse(
      code: SyncErrorCode.serviceUnavailable,
      message: message ?? 'Service temporarily unavailable',
      retryAfterSeconds: retryAfterSeconds,
    );
  }

  /// Creates a timeout error.
  factory ErrorResponse.timeout({String? message}) {
    return ErrorResponse(
      code: SyncErrorCode.timeout,
      message: message ?? 'Request timed out',
    );
  }

  /// Creates an invalid cursor error.
  factory ErrorResponse.invalidCursor(int cursor) {
    return ErrorResponse(
      code: SyncErrorCode.invalidCursor,
      message: 'Invalid cursor position: $cursor',
    );
  }

  /// Creates a not supported error.
  factory ErrorResponse.notSupported(String operation) {
    return ErrorResponse(
      code: SyncErrorCode.notSupported,
      message: 'Operation not supported: $operation',
    );
  }

  /// Deserializes from CBOR bytes.
  factory ErrorResponse.fromBytes(Uint8List bytes) {
    final map = decodeFromCbor(bytes);
    return ErrorResponse(
      code: SyncErrorCode.fromValue(map['code'] as int),
      message: map['message'] as String,
      details: map['details'] as String?,
      field: map['field'] as String?,
      retryAfterSeconds: map['retryAfterSeconds'] as int?,
      requestId: map['requestId'] as String?,
    );
  }

  /// The error code identifying the type of error.
  final SyncErrorCode code;

  /// Human-readable error message.
  final String message;

  /// Optional detailed description for debugging.
  final String? details;

  /// Optional field that caused the error.
  final String? field;

  /// Optional retry-after hint in seconds (for rate limiting).
  final int? retryAfterSeconds;

  /// Optional request ID for tracing.
  final String? requestId;

  /// Serializes to CBOR bytes.
  Uint8List toBytes() {
    return encodeToCbor({
      'code': code.value,
      'message': message,
      if (details != null) 'details': details,
      if (field != null) 'field': field,
      if (retryAfterSeconds != null) 'retryAfterSeconds': retryAfterSeconds,
      if (requestId != null) 'requestId': requestId,
    });
  }

  /// Whether this error is retryable.
  bool get isRetryable => switch (code) {
    SyncErrorCode.rateLimitExceeded ||
    SyncErrorCode.serviceUnavailable ||
    SyncErrorCode.timeout ||
    SyncErrorCode.internalError => true,
    _ => false,
  };

  /// Whether this error requires re-authentication.
  bool get requiresReauth => switch (code) {
    SyncErrorCode.authenticationFailed ||
    SyncErrorCode.authorizationFailed => true,
    _ => false,
  };

  @override
  String toString() {
    final buffer = StringBuffer('ErrorResponse(code: ${code.name}');
    buffer.write(', message: $message');
    if (details != null) buffer.write(', details: $details');
    if (field != null) buffer.write(', field: $field');
    if (retryAfterSeconds != null) {
      buffer.write(', retryAfter: ${retryAfterSeconds}s');
    }
    if (requestId != null) buffer.write(', requestId: $requestId');
    buffer.write(')');
    return buffer.toString();
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is ErrorResponse &&
        other.code == code &&
        other.message == message &&
        other.details == details &&
        other.field == field &&
        other.retryAfterSeconds == retryAfterSeconds &&
        other.requestId == requestId;
  }

  @override
  int get hashCode =>
      Object.hash(code, message, details, field, retryAfterSeconds, requestId);
}
