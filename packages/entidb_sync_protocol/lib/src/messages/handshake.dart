/// Handshake Messages
///
/// Protocol messages for initial client-server handshake.
library;

import 'dart:typed_data';

import 'package:meta/meta.dart';

import '../cbor/decoders.dart';
import '../cbor/encoders.dart';

/// Client information sent during handshake.
@immutable
class ClientInfo {
  /// Platform identifier (e.g., "android", "ios", "web", "windows").
  final String platform;

  /// Application version string.
  final String appVersion;

  /// Optional additional metadata.
  final Map<String, String>? metadata;

  const ClientInfo({
    required this.platform,
    required this.appVersion,
    this.metadata,
  });

  Map<String, dynamic> toMap() => {
    'platform': platform,
    'appVersion': appVersion,
    if (metadata != null) 'metadata': metadata,
  };

  factory ClientInfo.fromMap(Map<String, dynamic> map) {
    return ClientInfo(
      platform: map['platform'] as String,
      appVersion: map['appVersion'] as String,
      metadata: map['metadata'] != null
          ? Map<String, String>.from(map['metadata'] as Map)
          : null,
    );
  }

  @override
  String toString() =>
      'ClientInfo(platform: $platform, appVersion: $appVersion)';
}

/// Server capabilities advertised during handshake.
@immutable
class ServerCapabilities {
  /// Whether pull operations are supported.
  final bool pull;

  /// Whether push operations are supported.
  final bool push;

  /// Whether server-sent events are supported.
  final bool sse;

  const ServerCapabilities({
    this.pull = true,
    this.push = true,
    this.sse = false,
  });

  Map<String, dynamic> toMap() => {'pull': pull, 'push': push, 'sse': sse};

  factory ServerCapabilities.fromMap(Map<String, dynamic> map) {
    return ServerCapabilities(
      pull: map['pull'] as bool? ?? true,
      push: map['push'] as bool? ?? true,
      sse: map['sse'] as bool? ?? false,
    );
  }

  @override
  String toString() =>
      'ServerCapabilities(pull: $pull, push: $push, sse: $sse)';
}

/// Handshake request sent by client to initiate sync session.
///
/// POST /v1/handshake
@immutable
class HandshakeRequest {
  /// Database identifier.
  final String dbId;

  /// Device identifier (stable per client).
  final String deviceId;

  /// Client information for logging and compatibility checks.
  final ClientInfo clientInfo;

  const HandshakeRequest({
    required this.dbId,
    required this.deviceId,
    required this.clientInfo,
  });

  /// Serializes to CBOR bytes.
  Uint8List toBytes() {
    return encodeToCbor({
      'dbId': dbId,
      'deviceId': deviceId,
      'clientInfo': clientInfo.toMap(),
    });
  }

  /// Deserializes from CBOR bytes.
  factory HandshakeRequest.fromBytes(Uint8List bytes) {
    final map = decodeFromCbor(bytes);
    return HandshakeRequest(
      dbId: map['dbId'] as String,
      deviceId: map['deviceId'] as String,
      clientInfo: ClientInfo.fromMap(map['clientInfo'] as Map<String, dynamic>),
    );
  }

  @override
  String toString() => 'HandshakeRequest(dbId: $dbId, deviceId: $deviceId)';
}

/// Handshake response from server.
@immutable
class HandshakeResponse {
  /// Current server cursor position.
  ///
  /// Client should use this as the starting point for pull operations.
  final int serverCursor;

  /// Server capabilities.
  final ServerCapabilities capabilities;

  /// Optional session token for subsequent requests.
  final String? sessionToken;

  const HandshakeResponse({
    required this.serverCursor,
    required this.capabilities,
    this.sessionToken,
  });

  /// Serializes to CBOR bytes.
  Uint8List toBytes() {
    return encodeToCbor({
      'serverCursor': serverCursor,
      'capabilities': capabilities.toMap(),
      if (sessionToken != null) 'sessionToken': sessionToken,
    });
  }

  /// Deserializes from CBOR bytes.
  factory HandshakeResponse.fromBytes(Uint8List bytes) {
    final map = decodeFromCbor(bytes);
    return HandshakeResponse(
      serverCursor: map['serverCursor'] as int,
      capabilities: ServerCapabilities.fromMap(
        map['capabilities'] as Map<String, dynamic>,
      ),
      sessionToken: map['sessionToken'] as String?,
    );
  }

  @override
  String toString() =>
      'HandshakeResponse(serverCursor: $serverCursor, capabilities: $capabilities)';
}
