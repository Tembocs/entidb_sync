/// WebSocket Transport
///
/// WebSocket client for bidirectional real-time sync communication.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:entidb_sync_protocol/entidb_sync_protocol.dart';
import 'package:logging/logging.dart';

/// Configuration for WebSocket transport.
class WebSocketTransportConfig {
  /// WebSocket server URL (ws:// or wss://).
  final Uri serverUrl;

  /// Database identifier.
  final String dbId;

  /// Device identifier.
  final String deviceId;

  /// Function to provide auth token.
  final Future<String?> Function()? authTokenProvider;

  /// Reconnection delay (initial).
  final Duration reconnectDelay;

  /// Maximum reconnection delay.
  final Duration maxReconnectDelay;

  /// Ping interval.
  final Duration pingInterval;

  /// Request timeout.
  final Duration requestTimeout;

  /// Collections to subscribe to (null = all).
  final List<String>? collections;

  const WebSocketTransportConfig({
    required this.serverUrl,
    required this.dbId,
    required this.deviceId,
    this.authTokenProvider,
    this.reconnectDelay = const Duration(seconds: 1),
    this.maxReconnectDelay = const Duration(seconds: 30),
    this.pingInterval = const Duration(seconds: 30),
    this.requestTimeout = const Duration(seconds: 30),
    this.collections,
  });
}

/// WebSocket connection state.
enum WebSocketState {
  /// Not connected.
  disconnected,

  /// Attempting to connect.
  connecting,

  /// Connected and ready.
  connected,

  /// Reconnecting after disconnect.
  reconnecting,

  /// Permanently closed.
  closed,
}

/// Message types for WebSocket protocol (mirrors server).
enum WsMessageType {
  subscribe,
  subscribed,
  operations,
  ack,
  pull,
  pullResponse,
  push,
  pushResponse,
  ping,
  pong,
  error,
}

/// Represents a WebSocket message.
class WsMessage {
  final WsMessageType type;
  final String? id;
  final Map<String, dynamic> data;

  const WsMessage({required this.type, this.id, required this.data});

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

  String toJson() {
    return jsonEncode({
      'type': type.name,
      if (id != null) 'id': id,
      'data': data,
    });
  }
}

/// Callback for receiving real-time operations.
typedef OperationsCallback =
    void Function(List<SyncOperation> operations, int cursor);

/// WebSocket transport for bidirectional real-time sync.
class WebSocketTransport {
  final WebSocketTransportConfig _config;
  final Logger _log = Logger('WebSocketTransport');

  WebSocket? _socket;
  WebSocketState _state = WebSocketState.disconnected;
  Timer? _pingTimer;
  Timer? _reconnectTimer;
  int _reconnectAttempts = 0;
  int _messageCounter = 0;

  /// Pending request completers by message ID.
  final Map<String, Completer<WsMessage>> _pendingRequests = {};

  /// Stream controller for state changes.
  final StreamController<WebSocketState> _stateController =
      StreamController<WebSocketState>.broadcast();

  /// Stream controller for incoming operations.
  final StreamController<(List<SyncOperation>, int)> _operationsController =
      StreamController<(List<SyncOperation>, int)>.broadcast();

  /// Connection ID from server.
  String? _connectionId;

  /// Current server cursor.
  int _serverCursor = 0;

  WebSocketTransport({required WebSocketTransportConfig config})
    : _config = config;

  /// Current connection state.
  WebSocketState get state => _state;

  /// Stream of state changes.
  Stream<WebSocketState> get stateStream => _stateController.stream;

  /// Stream of real-time operations from server.
  Stream<(List<SyncOperation>, int)> get operationsStream =>
      _operationsController.stream;

  /// Whether currently connected.
  bool get isConnected => _state == WebSocketState.connected;

  /// Connection ID (available after connecting).
  String? get connectionId => _connectionId;

  /// Current server cursor.
  int get serverCursor => _serverCursor;

  /// Connects to the WebSocket server.
  Future<void> connect() async {
    if (_state == WebSocketState.connected ||
        _state == WebSocketState.connecting) {
      return;
    }

    _setState(WebSocketState.connecting);

    try {
      final url = _buildUrl();
      _log.info('Connecting to WebSocket: $url');

      _socket = await WebSocket.connect(url.toString());
      _socket!.listen(_onMessage, onError: _onError, onDone: _onDone);

      _startPingTimer();
      // Wait for subscribed message
      // The connection is considered complete when we receive 'subscribed'
    } catch (e) {
      _log.warning('Connection failed: $e');
      _scheduleReconnect();
    }
  }

  /// Disconnects from the server.
  Future<void> disconnect() async {
    _setState(WebSocketState.closed);
    _cleanup();
    await _socket?.close(1000, 'Client disconnect');
    _socket = null;
  }

  /// Pulls operations from the server via WebSocket.
  Future<PullResponse> pull({
    required int sinceCursor,
    int limit = 100,
    List<String>? collections,
  }) async {
    _ensureConnected();

    final response = await _sendRequest(WsMessageType.pull, {
      'sinceCursor': sinceCursor,
      'limit': limit,
      if (collections != null) 'collections': collections,
    });

    final opsData = (response.data['operations'] as List<dynamic>?) ?? [];
    final operations = opsData.map(_parseOperation).toList();

    return PullResponse(
      ops: operations,
      nextCursor: response.data['nextCursor'] as int,
      hasMore: response.data['hasMore'] as bool,
    );
  }

  /// Pushes operations to the server via WebSocket.
  Future<PushResponse> push(List<SyncOperation> ops) async {
    _ensureConnected();

    final opsData = ops.map(_operationToMap).toList();

    final response = await _sendRequest(WsMessageType.push, {
      'operations': opsData,
    });

    final conflictsData = (response.data['conflicts'] as List<dynamic>?) ?? [];
    final conflicts = conflictsData.map((c) {
      final map = c as Map<String, dynamic>;
      return Conflict(
        collection: map['collection'] as String,
        entityId: map['entityId'] as String,
        clientOp: ops.firstWhere(
          (op) =>
              op.collection == map['collection'] &&
              op.entityId == map['entityId'],
        ),
        serverState: ServerState(
          entityVersion: map['serverVersion'] as int,
          entityCbor: Uint8List(0),
          lastModified: DateTime.now(),
        ),
      );
    }).toList();

    return PushResponse(
      acknowledgedUpToOpId: response.data['acknowledgedUpToOpId'] as int,
      conflicts: conflicts,
    );
  }

  /// Updates subscription collections.
  Future<void> updateSubscription(List<String>? collections) async {
    if (!isConnected) return;

    _send(
      WsMessage(
        type: WsMessageType.subscribe,
        data: {if (collections != null) 'collections': collections},
      ),
    );
  }

  /// Acknowledges received operations.
  void acknowledgeOperations(int cursor) {
    if (!isConnected) return;

    _send(WsMessage(type: WsMessageType.ack, data: {'cursor': cursor}));
  }

  void _setState(WebSocketState newState) {
    if (_state != newState) {
      _state = newState;
      _stateController.add(newState);
    }
  }

  Uri _buildUrl() {
    final scheme = _config.serverUrl.scheme == 'https' ? 'wss' : 'ws';
    return _config.serverUrl.replace(
      scheme: scheme,
      path: '/v1/ws',
      queryParameters: {
        'deviceId': _config.deviceId,
        'dbId': _config.dbId,
        if (_config.collections != null)
          'collections': _config.collections!.join(','),
      },
    );
  }

  void _onMessage(dynamic data) {
    if (data is! String) return;

    try {
      final message = WsMessage.fromJson(data);
      _log.fine('Received: ${message.type}');

      switch (message.type) {
        case WsMessageType.subscribed:
          _connectionId = message.data['connectionId'] as String?;
          _serverCursor = message.data['cursor'] as int? ?? 0;
          _reconnectAttempts = 0;
          _setState(WebSocketState.connected);
          _log.info('Connected: $_connectionId, cursor: $_serverCursor');

        case WsMessageType.operations:
          _handleOperations(message);

        case WsMessageType.pullResponse:
        case WsMessageType.pushResponse:
          _handleResponse(message);

        case WsMessageType.pong:
          // Keepalive response, nothing to do
          break;

        case WsMessageType.error:
          _handleError(message);

        default:
          _log.warning('Unknown message type: ${message.type}');
      }
    } catch (e) {
      _log.warning('Failed to parse message: $e');
    }
  }

  void _handleOperations(WsMessage message) {
    final cursor = message.data['cursor'] as int? ?? 0;
    final opsData = (message.data['operations'] as List<dynamic>?) ?? [];
    final operations = opsData.map(_parseOperation).toList();

    _serverCursor = cursor;
    _operationsController.add((operations, cursor));

    // Send acknowledgment
    acknowledgeOperations(cursor);
  }

  void _handleResponse(WsMessage message) {
    final id = message.id;
    if (id != null && _pendingRequests.containsKey(id)) {
      _pendingRequests.remove(id)?.complete(message);
    }
  }

  void _handleError(WsMessage message) {
    final id = message.id;
    if (id != null && _pendingRequests.containsKey(id)) {
      _pendingRequests
          .remove(id)
          ?.completeError(
            WebSocketTransportException(
              message.data['message'] as String? ?? 'Unknown error',
              code: message.data['code'] as String?,
            ),
          );
    } else {
      _log.warning('Server error: ${message.data['message']}');
    }
  }

  void _onError(Object error) {
    _log.warning('WebSocket error: $error');
    _scheduleReconnect();
  }

  void _onDone() {
    _log.info('WebSocket closed');
    if (_state != WebSocketState.closed) {
      _scheduleReconnect();
    }
  }

  void _scheduleReconnect() {
    if (_state == WebSocketState.closed) return;

    _cleanup();
    _socket = null;
    _setState(WebSocketState.reconnecting);

    // Exponential backoff
    final delay = Duration(
      milliseconds:
          (_config.reconnectDelay.inMilliseconds *
                  (1 << _reconnectAttempts.clamp(0, 5)))
              .clamp(0, _config.maxReconnectDelay.inMilliseconds),
    );

    _reconnectAttempts++;
    _log.info(
      'Reconnecting in ${delay.inSeconds}s (attempt $_reconnectAttempts)',
    );

    _reconnectTimer = Timer(delay, () {
      if (_state == WebSocketState.reconnecting) {
        connect();
      }
    });
  }

  void _startPingTimer() {
    _pingTimer?.cancel();
    _pingTimer = Timer.periodic(_config.pingInterval, (_) {
      if (isConnected) {
        _send(
          WsMessage(
            type: WsMessageType.ping,
            data: {'timestamp': DateTime.now().millisecondsSinceEpoch},
          ),
        );
      }
    });
  }

  void _cleanup() {
    _pingTimer?.cancel();
    _pingTimer = null;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;

    // Fail pending requests
    for (final completer in _pendingRequests.values) {
      completer.completeError(WebSocketTransportException('Connection closed'));
    }
    _pendingRequests.clear();
  }

  void _ensureConnected() {
    if (!isConnected) {
      throw WebSocketTransportException('Not connected', code: 'not_connected');
    }
  }

  void _send(WsMessage message) {
    if (_socket == null) return;
    _socket!.add(message.toJson());
  }

  Future<WsMessage> _sendRequest(
    WsMessageType type,
    Map<String, dynamic> data,
  ) async {
    final id = '${_messageCounter++}';
    final completer = Completer<WsMessage>();
    _pendingRequests[id] = completer;

    _send(WsMessage(type: type, id: id, data: data));

    return completer.future.timeout(
      _config.requestTimeout,
      onTimeout: () {
        _pendingRequests.remove(id);
        throw WebSocketTransportException('Request timeout', code: 'timeout');
      },
    );
  }

  SyncOperation _parseOperation(dynamic data) {
    final map = data as Map<String, dynamic>;
    return SyncOperation(
      opId: map['opId'] as int,
      dbId: map['dbId'] as String,
      deviceId: map['deviceId'] as String,
      collection: map['collection'] as String,
      entityId: map['entityId'] as String,
      opType: OperationType.values.firstWhere((t) => t.name == map['opType']),
      entityVersion: map['entityVersion'] as int,
      entityCbor: map['entityCbor'] != null
          ? Uint8List.fromList((map['entityCbor'] as List<dynamic>).cast<int>())
          : null,
      timestampMs: map['timestampMs'] as int,
    );
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

  /// Disposes the transport.
  Future<void> dispose() async {
    await disconnect();
    await _stateController.close();
    await _operationsController.close();
  }
}

/// Exception thrown when WebSocket transport fails.
class WebSocketTransportException implements Exception {
  final String message;
  final String? code;

  WebSocketTransportException(this.message, {this.code});

  @override
  String toString() =>
      'WebSocketTransportException: $message${code != null ? ' (code: $code)' : ''}';
}
