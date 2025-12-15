/// SSE Subscriber
///
/// Client-side Server-Sent Events subscriber for real-time sync updates.
library;

import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'package:entidb_sync_protocol/entidb_sync_protocol.dart';

/// Event types received from SSE stream.
enum SseEventType {
  /// New operations available.
  operations,

  /// Keepalive ping.
  ping,

  /// Connection established.
  connected,

  /// Error occurred.
  error,

  /// Unknown event type.
  unknown,
}

/// Represents an event received from the SSE stream.
class SseReceivedEvent {
  /// Creates an SSE received event.
  const SseReceivedEvent({required this.type, required this.data, this.id});

  /// Event type.
  final SseEventType type;

  /// Event ID (for reconnection).
  final String? id;

  /// Raw data payload.
  final Map<String, dynamic> data;

  /// Gets the cursor from an operations or connected event.
  int? get cursor => data['cursor'] as int?;

  /// Gets operations from an operations event.
  List<SseOperationInfo> get operations {
    if (type != SseEventType.operations) return [];
    final ops = data['operations'] as List<dynamic>? ?? [];
    return ops
        .map((op) => SseOperationInfo.fromMap(op as Map<String, dynamic>))
        .toList();
  }

  /// Gets subscription ID from connected event.
  String? get subscriptionId => data['subscriptionId'] as String?;

  /// Gets error message from error event.
  String? get errorMessage => data['message'] as String?;

  @override
  String toString() => 'SseReceivedEvent(type: $type, id: $id, data: $data)';
}

/// Minimal operation info sent via SSE (without full entity data).
class SseOperationInfo {
  /// Creates SSE operation info.
  const SseOperationInfo({
    required this.opId,
    required this.dbId,
    required this.deviceId,
    required this.collection,
    required this.entityId,
    required this.opType,
    required this.entityVersion,
    required this.timestampMs,
  });

  /// Creates from a map.
  factory SseOperationInfo.fromMap(Map<String, dynamic> map) {
    return SseOperationInfo(
      opId: map['opId'] as int,
      dbId: map['dbId'] as String,
      deviceId: map['deviceId'] as String,
      collection: map['collection'] as String,
      entityId: map['entityId'] as String,
      opType: OperationType.values.firstWhere(
        (OperationType t) => t.name == map['opType'],
        orElse: () => OperationType.upsert,
      ),
      entityVersion: map['entityVersion'] as int,
      timestampMs: map['timestampMs'] as int,
    );
  }

  /// Operation ID.
  final int opId;

  /// Database ID.
  final String dbId;

  /// Device ID that created the operation.
  final String deviceId;

  /// Collection name.
  final String collection;

  /// Entity ID.
  final String entityId;

  /// Operation type.
  final OperationType opType;

  /// Entity version.
  final int entityVersion;

  /// Server timestamp.
  final int timestampMs;
}

/// Connection state for SSE subscriber.
enum SseConnectionState {
  /// Not connected.
  disconnected,

  /// Attempting to connect.
  connecting,

  /// Connected and receiving events.
  connected,

  /// Connection failed with error.
  error,
}

/// Configuration for SSE subscriber.
class SseSubscriberConfig {
  /// Creates SSE subscriber configuration.
  const SseSubscriberConfig({
    required this.serverUrl,
    required this.deviceId,
    this.collections,
    this.authToken,
    this.autoReconnect = true,
    this.reconnectDelay = const Duration(seconds: 3),
    this.maxReconnectAttempts = 0,
  });

  /// Server base URL.
  final String serverUrl;

  /// Device ID for the subscription.
  final String deviceId;

  /// Collections to subscribe to (null = all).
  final List<String>? collections;

  /// Authorization token (optional).
  final String? authToken;

  /// Whether to automatically reconnect on disconnect.
  final bool autoReconnect;

  /// Delay between reconnection attempts.
  final Duration reconnectDelay;

  /// Maximum reconnection attempts (0 = infinite).
  final int maxReconnectAttempts;
}

/// Subscribes to server-sent events for real-time sync updates.
class SseSubscriber {
  /// Creates an SSE subscriber.
  SseSubscriber(this.config);

  /// Configuration.
  final SseSubscriberConfig config;

  /// HTTP client (for managing connection lifecycle).
  http.Client? _client;

  /// Event stream controller.
  final StreamController<SseReceivedEvent> _eventController =
      StreamController<SseReceivedEvent>.broadcast();

  /// State stream controller.
  final StreamController<SseConnectionState> _stateController =
      StreamController<SseConnectionState>.broadcast();

  /// Current connection state.
  SseConnectionState _state = SseConnectionState.disconnected;

  /// Current subscription ID (received from server).
  String? _subscriptionId;

  /// Last event ID received (for reconnection).
  String? _lastEventId;

  /// Reconnection attempt counter.
  int _reconnectAttempts = 0;

  /// Whether subscriber is disposed.
  bool _disposed = false;

  /// Reconnection timer.
  Timer? _reconnectTimer;

  /// Stream of received events.
  Stream<SseReceivedEvent> get events => _eventController.stream;

  /// Stream of connection state changes.
  Stream<SseConnectionState> get stateChanges => _stateController.stream;

  /// Current connection state.
  SseConnectionState get state => _state;

  /// Current subscription ID.
  String? get subscriptionId => _subscriptionId;

  /// Whether currently connected.
  bool get isConnected => _state == SseConnectionState.connected;

  /// Connects to the SSE endpoint.
  Future<void> connect() async {
    if (_disposed) {
      throw StateError('Subscriber has been disposed');
    }

    if (_state == SseConnectionState.connecting ||
        _state == SseConnectionState.connected) {
      return;
    }

    _setState(SseConnectionState.connecting);
    _client = http.Client();

    try {
      final uri = _buildUri();
      final request = http.Request('GET', uri);

      // Set headers
      request.headers['Accept'] = 'text/event-stream';
      request.headers['Cache-Control'] = 'no-cache';
      if (config.authToken != null) {
        request.headers['Authorization'] = 'Bearer ${config.authToken}';
      }
      if (_lastEventId != null) {
        request.headers['Last-Event-ID'] = _lastEventId!;
      }

      final streamedResponse = await _client!.send(request);

      if (streamedResponse.statusCode != 200) {
        throw Exception(
          'SSE connection failed: ${streamedResponse.statusCode}',
        );
      }

      _reconnectAttempts = 0;

      // Process the SSE stream
      await _processStream(streamedResponse.stream);
    } catch (e) {
      _setState(SseConnectionState.error);
      _handleDisconnect(e);
    }
  }

  /// Disconnects from the SSE endpoint.
  void disconnect() {
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _client?.close();
    _client = null;
    _setState(SseConnectionState.disconnected);
    _subscriptionId = null;
  }

  /// Disposes the subscriber and releases resources.
  void dispose() {
    _disposed = true;
    disconnect();
    _eventController.close();
    _stateController.close();
  }

  Uri _buildUri() {
    final baseUrl = config.serverUrl.endsWith('/')
        ? config.serverUrl.substring(0, config.serverUrl.length - 1)
        : config.serverUrl;

    final params = <String, String>{'deviceId': config.deviceId};
    if (config.collections != null && config.collections!.isNotEmpty) {
      params['collections'] = config.collections!.join(',');
    }

    return Uri.parse('$baseUrl/v1/events').replace(queryParameters: params);
  }

  Future<void> _processStream(Stream<List<int>> stream) async {
    final buffer = StringBuffer();

    await for (final chunk in stream.transform(utf8.decoder)) {
      buffer.write(chunk);

      // Parse complete events from buffer
      final content = buffer.toString();
      final events = _parseEvents(content);

      if (events.isNotEmpty) {
        // Keep unparsed content in buffer
        final lastEventEnd = content.lastIndexOf('\n\n');
        if (lastEventEnd >= 0) {
          buffer.clear();
          buffer.write(content.substring(lastEventEnd + 2));
        }

        for (final event in events) {
          _handleEvent(event);
        }
      }
    }

    // Stream ended
    _handleDisconnect(null);
  }

  List<SseReceivedEvent> _parseEvents(String content) {
    final events = <SseReceivedEvent>[];
    final rawEvents = content.split('\n\n');

    for (final rawEvent in rawEvents) {
      if (rawEvent.trim().isEmpty) continue;

      String? eventType;
      String? eventId;
      String? eventData;

      for (final line in rawEvent.split('\n')) {
        if (line.startsWith('event:')) {
          eventType = line.substring(6).trim();
        } else if (line.startsWith('id:')) {
          eventId = line.substring(3).trim();
        } else if (line.startsWith('data:')) {
          eventData = line.substring(5).trim();
        }
      }

      if (eventType != null && eventData != null) {
        try {
          final data = jsonDecode(eventData) as Map<String, dynamic>;
          events.add(
            SseReceivedEvent(
              type: _parseEventType(eventType),
              id: eventId,
              data: data,
            ),
          );
        } catch (_) {
          // Skip malformed events
        }
      }
    }

    return events;
  }

  SseEventType _parseEventType(String type) {
    switch (type) {
      case 'operations':
        return SseEventType.operations;
      case 'ping':
        return SseEventType.ping;
      case 'connected':
        return SseEventType.connected;
      case 'error':
        return SseEventType.error;
      default:
        return SseEventType.unknown;
    }
  }

  void _handleEvent(SseReceivedEvent event) {
    if (event.id != null) {
      _lastEventId = event.id;
    }

    switch (event.type) {
      case SseEventType.connected:
        _subscriptionId = event.subscriptionId;
        _setState(SseConnectionState.connected);
        break;
      case SseEventType.error:
        _setState(SseConnectionState.error);
        break;
      case SseEventType.operations:
      case SseEventType.ping:
      case SseEventType.unknown:
        break;
    }

    _eventController.add(event);
  }

  void _handleDisconnect(Object? error) {
    _client?.close();
    _client = null;

    if (_disposed) return;

    if (config.autoReconnect &&
        (config.maxReconnectAttempts == 0 ||
            _reconnectAttempts < config.maxReconnectAttempts)) {
      _reconnectAttempts++;
      _reconnectTimer = Timer(config.reconnectDelay, () {
        if (!_disposed) {
          connect();
        }
      });
    } else {
      _setState(SseConnectionState.disconnected);
    }
  }

  void _setState(SseConnectionState newState) {
    if (_state != newState) {
      _state = newState;
      _stateController.add(newState);
    }
  }
}
