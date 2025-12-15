/// WebSocket Manager
///
/// Manages WebSocket connections for bidirectional real-time sync.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:entidb_sync_protocol/entidb_sync_protocol.dart';

/// Configuration for WebSocket connections.
class WebSocketConfig {
  /// Creates WebSocket configuration.
  const WebSocketConfig({
    this.keepAliveIntervalSeconds = 30,
    this.pingTimeoutSeconds = 10,
    this.maxConnectionsPerDevice = 3,
    this.maxTotalConnections = 1000,
    this.maxMessageSize = 1024 * 1024, // 1MB
  });

  /// Default configuration.
  static const WebSocketConfig defaultConfig = WebSocketConfig();

  /// How often to send keepalive pings (in seconds).
  final int keepAliveIntervalSeconds;

  /// Ping timeout (in seconds).
  final int pingTimeoutSeconds;

  /// Maximum connections per device ID.
  final int maxConnectionsPerDevice;

  /// Maximum total connections.
  final int maxTotalConnections;

  /// Maximum message size in bytes.
  final int maxMessageSize;
}

/// Message types for WebSocket protocol.
enum WsMessageType {
  /// Client requests to subscribe.
  subscribe,

  /// Server confirms subscription.
  subscribed,

  /// Server sends operations.
  operations,

  /// Client acknowledges operations.
  ack,

  /// Client requests pull.
  pull,

  /// Server responds to pull.
  pullResponse,

  /// Client pushes operations.
  push,

  /// Server confirms push.
  pushResponse,

  /// Keepalive ping.
  ping,

  /// Keepalive pong.
  pong,

  /// Error message.
  error,
}

/// Represents a WebSocket message.
class WsMessage {
  /// Creates a WebSocket message.
  const WsMessage({required this.type, required this.data, this.id});

  /// Parses a WebSocket message from JSON string.
  factory WsMessage.fromJson(String json) {
    final map = jsonDecode(json) as Map<String, dynamic>;
    return WsMessage(
      type: WsMessageType.values.firstWhere(
        (t) => t.name == map['type'],
        orElse: () => WsMessageType.error,
      ),
      id: map['id'] as String?,
      data: (map['data'] as Map<String, dynamic>?) ?? {},
    );
  }

  /// Creates an operations message.
  factory WsMessage.operations({
    required int cursor,
    required List<Map<String, dynamic>> operations,
    String? id,
  }) {
    return WsMessage(
      type: WsMessageType.operations,
      id: id,
      data: {
        'cursor': cursor,
        'operations': operations,
        'count': operations.length,
      },
    );
  }

  /// Creates a subscribed confirmation message.
  factory WsMessage.subscribed({
    required String connectionId,
    required int currentCursor,
  }) {
    return WsMessage(
      type: WsMessageType.subscribed,
      data: {'connectionId': connectionId, 'cursor': currentCursor},
    );
  }

  /// Creates a pull response message.
  factory WsMessage.pullResponse({
    required List<Map<String, dynamic>> operations,
    required int nextCursor,
    required bool hasMore,
    String? id,
  }) {
    return WsMessage(
      type: WsMessageType.pullResponse,
      id: id,
      data: {
        'operations': operations,
        'nextCursor': nextCursor,
        'hasMore': hasMore,
      },
    );
  }

  /// Creates a push response message.
  factory WsMessage.pushResponse({
    required int acknowledgedUpToOpId,
    required List<Map<String, dynamic>> conflicts,
    String? id,
  }) {
    return WsMessage(
      type: WsMessageType.pushResponse,
      id: id,
      data: {
        'acknowledgedUpToOpId': acknowledgedUpToOpId,
        'conflicts': conflicts,
      },
    );
  }

  /// Creates a ping message.
  factory WsMessage.ping() {
    return WsMessage(
      type: WsMessageType.ping,
      data: {'timestamp': DateTime.now().millisecondsSinceEpoch},
    );
  }

  /// Creates a pong message.
  factory WsMessage.pong(int timestamp) {
    return WsMessage(
      type: WsMessageType.pong,
      data: {
        'timestamp': timestamp,
        'serverTime': DateTime.now().millisecondsSinceEpoch,
      },
    );
  }

  /// Creates an error message.
  factory WsMessage.error({required String message, String? code, String? id}) {
    return WsMessage(
      type: WsMessageType.error,
      id: id,
      data: {'message': message, if (code != null) 'code': code},
    );
  }

  /// Message type.
  final WsMessageType type;

  /// Message ID for correlation.
  final String? id;

  /// Message payload.
  final Map<String, dynamic> data;

  /// Converts to JSON string.
  String toJson() {
    return jsonEncode({
      'type': type.name,
      if (id != null) 'id': id,
      'data': data,
    });
  }
}

/// Represents a client WebSocket connection.
class WsConnection {
  /// Creates a new WebSocket connection.
  WsConnection({
    required this.connectionId,
    required this.deviceId,
    required this.dbId,
    required this.socket,
    this.collections,
  }) : connectedAt = DateTime.now(),
       _incomingController = StreamController<WsMessage>.broadcast();

  /// Unique connection ID.
  final String connectionId;

  /// Device ID of the client.
  final String deviceId;

  /// Database ID.
  final String dbId;

  /// Collections to filter (null = all collections).
  List<String>? collections;

  /// The underlying WebSocket.
  final WebSocket socket;

  /// When the connection was established.
  final DateTime connectedAt;

  /// Number of messages sent.
  int messagesSent = 0;

  /// Number of messages received.
  int messagesReceived = 0;

  /// Last ping time.
  DateTime? lastPingTime;

  /// Whether currently waiting for pong.
  bool awaitingPong = false;

  /// Stream controller for incoming messages.
  final StreamController<WsMessage> _incomingController;

  /// Stream of incoming messages.
  Stream<WsMessage> get incoming => _incomingController.stream;

  /// Whether the connection is still open.
  bool get isOpen => socket.closeCode == null;

  /// Sends a message to the client.
  void send(WsMessage message) {
    if (!isOpen) return;
    socket.add(message.toJson());
    messagesSent++;
  }

  /// Closes the connection.
  Future<void> close([int? code, String? reason]) async {
    await socket.close(code, reason);
    await _incomingController.close();
  }
}

/// Callback for processing pull requests.
typedef PullHandler = Future<PullResponse> Function(PullRequest request);

/// Callback for processing push requests.
typedef PushHandler = Future<PushResponse> Function(PushRequest request);

/// Manages WebSocket connections for real-time sync.
class WebSocketManager {
  /// Creates a WebSocket manager.
  WebSocketManager({
    required this.onPull,
    required this.onPush,
    required this.getCurrentCursor,
    this.config = WebSocketConfig.defaultConfig,
  }) {
    _startKeepalive();
  }

  /// Configuration.
  final WebSocketConfig config;

  /// Pull request handler.
  final PullHandler onPull;

  /// Push request handler.
  final PushHandler onPush;

  /// Current server cursor getter.
  final int Function() getCurrentCursor;

  /// Active connections by connection ID.
  final Map<String, WsConnection> _connections = {};

  /// Connections by device ID.
  final Map<String, Set<String>> _deviceConnections = {};

  /// Keepalive timer.
  Timer? _keepAliveTimer;

  /// Event counter for message IDs.
  int _eventCounter = 0;

  /// Handles a new WebSocket connection upgrade.
  ///
  /// Returns true if connection was accepted, false otherwise.
  Future<bool> handleConnection(
    WebSocket socket,
    String deviceId,
    String dbId, {
    List<String>? collections,
  }) async {
    // Check total connection limit
    if (_connections.length >= config.maxTotalConnections) {
      socket.add(
        WsMessage.error(
          message: 'Server at capacity',
          code: 'capacity_exceeded',
        ).toJson(),
      );
      await socket.close(1013, 'Try again later');
      return false;
    }

    // Check per-device limit
    final deviceConns = _deviceConnections[deviceId] ?? <String>{};
    if (deviceConns.length >= config.maxConnectionsPerDevice) {
      // Close oldest connection for this device
      final oldest = deviceConns.first;
      await _closeConnection(oldest, 1000, 'Replaced by new connection');
    }

    // Create connection
    final connectionId = _generateConnectionId(deviceId);
    final connection = WsConnection(
      connectionId: connectionId,
      deviceId: deviceId,
      dbId: dbId,
      socket: socket,
      collections: collections,
    );

    _connections[connectionId] = connection;
    _deviceConnections
        .putIfAbsent(deviceId, () => <String>{})
        .add(connectionId);

    // Send subscribed confirmation
    connection.send(
      WsMessage.subscribed(
        connectionId: connectionId,
        currentCursor: getCurrentCursor(),
      ),
    );

    // Start listening for messages
    _listenToConnection(connection);

    return true;
  }

  /// Broadcasts operations to all relevant connections.
  void broadcast(List<SyncOperation> operations, int cursor) {
    if (operations.isEmpty || _connections.isEmpty) return;

    _eventCounter++;
    final eventId = '$cursor-$_eventCounter';

    for (final connection in _connections.values) {
      if (!connection.isOpen) continue;

      // Filter by collections if specified
      final relevantOps = connection.collections == null
          ? operations
          : operations
                .where((op) => connection.collections!.contains(op.collection))
                .toList();

      if (relevantOps.isEmpty) continue;

      // Convert to JSON-serializable format
      final opsData = relevantOps.map(_operationToMap).toList();

      connection.send(
        WsMessage.operations(cursor: cursor, operations: opsData, id: eventId),
      );
    }
  }

  /// Gets connection count.
  int get connectionCount => _connections.length;

  /// Gets active device count.
  int get activeDeviceCount => _deviceConnections.length;

  /// Gets connection stats.
  Map<String, dynamic> get stats => {
    'connections': connectionCount,
    'devices': activeDeviceCount,
    'messagesSent': _connections.values.fold<int>(
      0,
      (sum, conn) => sum + conn.messagesSent,
    ),
    'messagesReceived': _connections.values.fold<int>(
      0,
      (sum, conn) => sum + conn.messagesReceived,
    ),
  };

  /// Closes a specific connection.
  Future<void> closeConnection(String connectionId) async {
    await _closeConnection(connectionId, 1000, 'Server closed connection');
  }

  /// Disposes the manager.
  Future<void> dispose() async {
    _keepAliveTimer?.cancel();
    for (final connectionId in _connections.keys.toList()) {
      await _closeConnection(connectionId, 1001, 'Server shutting down');
    }
    _connections.clear();
    _deviceConnections.clear();
  }

  void _listenToConnection(WsConnection connection) {
    connection.socket.listen(
      (dynamic data) {
        if (data is String) {
          try {
            final message = WsMessage.fromJson(data);
            connection.messagesReceived++;
            _handleMessage(connection, message);
          } catch (e) {
            connection.send(
              WsMessage.error(
                message: 'Invalid message format: $e',
                code: 'invalid_message',
              ),
            );
          }
        }
      },
      onError: (Object error) {
        _closeConnection(connection.connectionId, 1011, 'Error: $error');
      },
      onDone: () {
        _removeConnection(connection.connectionId);
      },
    );
  }

  Future<void> _handleMessage(
    WsConnection connection,
    WsMessage message,
  ) async {
    switch (message.type) {
      case WsMessageType.subscribe:
        // Update collections filter
        final collections = (message.data['collections'] as List<dynamic>?)
            ?.cast<String>();
        connection.collections = collections;
        connection.send(
          WsMessage.subscribed(
            connectionId: connection.connectionId,
            currentCursor: getCurrentCursor(),
          ),
        );

      case WsMessageType.pull:
        await _handlePull(connection, message);

      case WsMessageType.push:
        await _handlePush(connection, message);

      case WsMessageType.ping:
        final timestamp = message.data['timestamp'] as int? ?? 0;
        connection.send(WsMessage.pong(timestamp));

      case WsMessageType.pong:
        connection.awaitingPong = false;

      case WsMessageType.ack:
        // Client acknowledged operations, nothing to do server-side
        break;

      default:
        connection.send(
          WsMessage.error(
            message: 'Unknown message type: ${message.type}',
            code: 'unknown_type',
            id: message.id,
          ),
        );
    }
  }

  Future<void> _handlePull(WsConnection connection, WsMessage message) async {
    try {
      final sinceCursor = message.data['sinceCursor'] as int? ?? 0;
      final limit = message.data['limit'] as int? ?? 100;
      final collections = (message.data['collections'] as List<dynamic>?)
          ?.cast<String>();

      final request = PullRequest(
        dbId: connection.dbId,
        sinceCursor: sinceCursor,
        limit: limit,
        collections: collections,
      );

      final response = await onPull(request);

      final opsData = response.ops.map(_operationToMap).toList();

      connection.send(
        WsMessage.pullResponse(
          operations: opsData,
          nextCursor: response.nextCursor,
          hasMore: response.hasMore,
          id: message.id,
        ),
      );
    } catch (e) {
      connection.send(
        WsMessage.error(
          message: 'Pull failed: $e',
          code: 'pull_error',
          id: message.id,
        ),
      );
    }
  }

  Future<void> _handlePush(WsConnection connection, WsMessage message) async {
    try {
      final opsData = (message.data['operations'] as List<dynamic>?) ?? [];
      final operations = opsData.map((opData) {
        final map = opData as Map<String, dynamic>;
        return SyncOperation(
          opId: map['opId'] as int,
          dbId: map['dbId'] as String,
          deviceId: map['deviceId'] as String,
          collection: map['collection'] as String,
          entityId: map['entityId'] as String,
          opType: OperationType.values.firstWhere(
            (t) => t.name == map['opType'],
          ),
          entityVersion: map['entityVersion'] as int,
          entityCbor: map['entityCbor'] != null
              ? Uint8List.fromList(
                  (map['entityCbor'] as List<dynamic>).cast<int>(),
                )
              : null,
          timestampMs: map['timestampMs'] as int,
        );
      }).toList();

      final request = PushRequest(
        dbId: connection.dbId,
        deviceId: connection.deviceId,
        ops: operations,
      );

      final response = await onPush(request);

      final conflictsData = response.conflicts
          .map(
            (c) => {
              'collection': c.collection,
              'entityId': c.entityId,
              'serverVersion': c.serverState.entityVersion,
            },
          )
          .toList();

      connection.send(
        WsMessage.pushResponse(
          acknowledgedUpToOpId: response.acknowledgedUpToOpId,
          conflicts: conflictsData,
          id: message.id,
        ),
      );
    } catch (e) {
      connection.send(
        WsMessage.error(
          message: 'Push failed: $e',
          code: 'push_error',
          id: message.id,
        ),
      );
    }
  }

  void _startKeepalive() {
    _keepAliveTimer = Timer.periodic(
      Duration(seconds: config.keepAliveIntervalSeconds),
      (_) => _sendKeepalive(),
    );
  }

  void _sendKeepalive() {
    final now = DateTime.now();
    final pingMessage = WsMessage.ping();

    for (final connection in _connections.values.toList()) {
      if (!connection.isOpen) {
        _removeConnection(connection.connectionId);
        continue;
      }

      // Check for ping timeout
      if (connection.awaitingPong &&
          connection.lastPingTime != null &&
          now.difference(connection.lastPingTime!).inSeconds >
              config.pingTimeoutSeconds) {
        _closeConnection(connection.connectionId, 1002, 'Ping timeout');
        continue;
      }

      connection.lastPingTime = now;
      connection.awaitingPong = true;
      connection.send(pingMessage);
    }
  }

  Future<void> _closeConnection(
    String connectionId,
    int code,
    String reason,
  ) async {
    final connection = _connections[connectionId];
    if (connection != null) {
      await connection.close(code, reason);
      _removeConnection(connectionId);
    }
  }

  void _removeConnection(String connectionId) {
    final connection = _connections.remove(connectionId);
    if (connection != null) {
      _deviceConnections[connection.deviceId]?.remove(connectionId);
      if (_deviceConnections[connection.deviceId]?.isEmpty ?? false) {
        _deviceConnections.remove(connection.deviceId);
      }
    }
  }

  String _generateConnectionId(String deviceId) {
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    return 'ws-$deviceId-$timestamp-${_connections.length}';
  }

  Map<String, dynamic> _operationToMap(SyncOperation op) => {
    'opId': op.opId,
    'dbId': op.dbId,
    'deviceId': op.deviceId,
    'collection': op.collection,
    'entityId': op.entityId,
    'opType': op.opType.name,
    'entityVersion': op.entityVersion,
    'timestampMs': op.timestampMs,
    if (op.entityCbor != null) 'entityCbor': op.entityCbor!.toList(),
  };
}
