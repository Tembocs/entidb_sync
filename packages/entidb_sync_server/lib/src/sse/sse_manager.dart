/// Server-Sent Events Manager
///
/// Manages SSE connections for real-time sync updates.
library;

import 'dart:async';
import 'dart:convert';

import 'package:entidb_sync_protocol/entidb_sync_protocol.dart';

/// Configuration for SSE connections.
class SseConfig {
  /// Creates SSE configuration.
  const SseConfig({
    this.keepAliveIntervalSeconds = 30,
    this.maxConnectionsPerDevice = 3,
    this.maxTotalConnections = 1000,
  });

  /// How often to send keepalive pings (in seconds).
  final int keepAliveIntervalSeconds;

  /// Maximum connections per device ID.
  final int maxConnectionsPerDevice;

  /// Maximum total connections.
  final int maxTotalConnections;

  /// Default configuration.
  static const SseConfig defaultConfig = SseConfig();
}

/// Represents a client SSE subscription.
class SseSubscription {
  /// Creates a new SSE subscription.
  SseSubscription({
    required this.subscriptionId,
    required this.deviceId,
    this.collections,
  }) : _controller = StreamController<String>.broadcast(),
       createdAt = DateTime.now();

  /// Unique subscription ID.
  final String subscriptionId;

  /// Device ID of the subscriber.
  final String deviceId;

  /// Collections to filter (null = all collections).
  final List<String>? collections;

  final StreamController<String> _controller;

  /// When the subscription was created.
  final DateTime createdAt;

  /// Number of events sent.
  int eventsSent = 0;

  /// The event stream.
  Stream<String> get stream => _controller.stream;

  /// Whether this subscription is still active.
  bool get isActive => !_controller.isClosed;

  /// Sends an SSE event to this subscriber.
  void sendEvent(SseEvent event) {
    if (_controller.isClosed) return;

    final data = event.toSseString();
    _controller.add(data);
    eventsSent++;
  }

  /// Closes the subscription.
  void close() {
    if (!_controller.isClosed) {
      _controller.close();
    }
  }
}

/// Types of SSE events.
enum SseEventType {
  /// New operations available.
  operations,

  /// Keepalive ping.
  ping,

  /// Connection established.
  connected,

  /// Error occurred.
  error,
}

/// Represents an SSE event.
class SseEvent {
  /// Creates an SSE event.
  const SseEvent({required this.type, required this.data, this.id});

  /// Creates an operations event.
  factory SseEvent.operations({
    required int cursor,
    required List<Map<String, dynamic>> operations,
    String? id,
  }) {
    return SseEvent(
      type: SseEventType.operations,
      id: id,
      data: {
        'cursor': cursor,
        'operations': operations,
        'count': operations.length,
      },
    );
  }

  /// Creates a ping event.
  factory SseEvent.ping() {
    return SseEvent(
      type: SseEventType.ping,
      data: {'timestamp': DateTime.now().millisecondsSinceEpoch},
    );
  }

  /// Creates a connected event.
  factory SseEvent.connected({
    required String subscriptionId,
    required int currentCursor,
  }) {
    return SseEvent(
      type: SseEventType.connected,
      data: {'subscriptionId': subscriptionId, 'cursor': currentCursor},
    );
  }

  /// Creates an error event.
  factory SseEvent.error({required String message, String? code}) {
    return SseEvent(
      type: SseEventType.error,
      data: {'message': message, if (code != null) 'code': code},
    );
  }

  /// Event type.
  final SseEventType type;

  /// Event ID (for reconnection).
  final String? id;

  /// Event data payload.
  final Map<String, dynamic> data;

  /// Converts to SSE format string.
  String toSseString() {
    final buffer = StringBuffer();

    buffer.writeln('event: ${type.name}');
    if (id != null) {
      buffer.writeln('id: $id');
    }
    buffer.writeln('data: ${jsonEncode(data)}');
    buffer.writeln(); // Empty line marks end of event

    return buffer.toString();
  }
}

/// Manages SSE connections and broadcasts operations.
class SseManager {
  /// Creates an SSE manager.
  SseManager({this.config = SseConfig.defaultConfig}) {
    _startKeepalive();
  }

  /// Configuration.
  final SseConfig config;

  /// Active subscriptions by subscription ID.
  final Map<String, SseSubscription> _subscriptions = {};

  /// Subscriptions by device ID.
  final Map<String, Set<String>> _deviceSubscriptions = {};

  /// Keepalive timer.
  Timer? _keepAliveTimer;

  /// Operation counter for event IDs.
  int _eventCounter = 0;

  /// Creates a new subscription for a device.
  ///
  /// Returns the subscription, or null if limits are exceeded.
  SseSubscription? subscribe({
    required String deviceId,
    List<String>? collections,
  }) {
    // Check total connection limit
    if (_subscriptions.length >= config.maxTotalConnections) {
      return null;
    }

    // Check per-device limit
    final deviceSubs = _deviceSubscriptions[deviceId] ?? <String>{};
    if (deviceSubs.length >= config.maxConnectionsPerDevice) {
      // Close oldest subscription for this device
      final oldest = deviceSubs.first;
      unsubscribe(oldest);
    }

    // Create subscription
    final subscriptionId = _generateSubscriptionId(deviceId);
    final subscription = SseSubscription(
      subscriptionId: subscriptionId,
      deviceId: deviceId,
      collections: collections,
    );

    _subscriptions[subscriptionId] = subscription;
    _deviceSubscriptions
        .putIfAbsent(deviceId, () => <String>{})
        .add(subscriptionId);

    return subscription;
  }

  /// Removes a subscription.
  void unsubscribe(String subscriptionId) {
    final subscription = _subscriptions.remove(subscriptionId);
    if (subscription != null) {
      subscription.close();
      _deviceSubscriptions[subscription.deviceId]?.remove(subscriptionId);

      // Clean up empty device entry
      if (_deviceSubscriptions[subscription.deviceId]?.isEmpty ?? false) {
        _deviceSubscriptions.remove(subscription.deviceId);
      }
    }
  }

  /// Broadcasts operations to all relevant subscribers.
  ///
  /// Called by SyncService when operations are pushed.
  void broadcast(List<SyncOperation> operations, int cursor) {
    if (operations.isEmpty || _subscriptions.isEmpty) return;

    _eventCounter++;
    final eventId = '$cursor-$_eventCounter';

    for (final subscription in _subscriptions.values) {
      if (!subscription.isActive) continue;

      // Filter by collections if specified
      final relevantOps = subscription.collections == null
          ? operations
          : operations
                .where(
                  (op) => subscription.collections!.contains(op.collection),
                )
                .toList();

      if (relevantOps.isEmpty) continue;

      // Convert to JSON-serializable format
      final opsData = relevantOps.map(_operationToMap).toList();

      subscription.sendEvent(
        SseEvent.operations(cursor: cursor, operations: opsData, id: eventId),
      );
    }
  }

  /// Sends the connected event to a subscription.
  void sendConnectedEvent(SseSubscription subscription, int currentCursor) {
    subscription.sendEvent(
      SseEvent.connected(
        subscriptionId: subscription.subscriptionId,
        currentCursor: currentCursor,
      ),
    );
  }

  /// Gets subscription count.
  int get subscriptionCount => _subscriptions.length;

  /// Gets active device count.
  int get activeDeviceCount => _deviceSubscriptions.length;

  /// Gets subscription stats.
  Map<String, dynamic> get stats => {
    'subscriptions': subscriptionCount,
    'devices': activeDeviceCount,
    'eventsSent': _subscriptions.values.fold<int>(
      0,
      (sum, sub) => sum + sub.eventsSent,
    ),
  };

  /// Disposes the manager.
  void dispose() {
    _keepAliveTimer?.cancel();
    for (final subscription in _subscriptions.values) {
      subscription.close();
    }
    _subscriptions.clear();
    _deviceSubscriptions.clear();
  }

  void _startKeepalive() {
    _keepAliveTimer = Timer.periodic(
      Duration(seconds: config.keepAliveIntervalSeconds),
      (_) => _sendKeepalive(),
    );
  }

  void _sendKeepalive() {
    final pingEvent = SseEvent.ping();
    for (final subscription in _subscriptions.values) {
      if (subscription.isActive) {
        subscription.sendEvent(pingEvent);
      }
    }

    // Clean up closed subscriptions
    final closed = _subscriptions.entries
        .where((e) => !e.value.isActive)
        .map((e) => e.key)
        .toList();

    for (final id in closed) {
      unsubscribe(id);
    }
  }

  String _generateSubscriptionId(String deviceId) {
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    return '$deviceId-$timestamp-${_subscriptions.length}';
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
    // entityCbor is omitted - clients should pull for full data
  };
}
