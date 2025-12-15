/// Sync Configuration Model
///
/// Client-side configuration for EntiDB synchronization.
library;

import 'package:meta/meta.dart';

/// Configuration for sync client.
@immutable
class SyncConfig {
  /// Creates a sync configuration.
  const SyncConfig({
    required this.serverUrl,
    required this.dbId,
    required this.deviceId,
    required this.authTokenProvider,
    this.syncIntervalSeconds = 60,
    this.maxBatchSize = 100,
    this.retryConfig = const RetryConfig(),
  });

  /// Server URL (HTTPS required in production).
  final Uri serverUrl;

  /// Database identifier (globally unique).
  final String dbId;

  /// Device identifier (stable per device).
  final String deviceId;

  /// Auth token provider function.
  final Future<String> Function() authTokenProvider;

  /// Sync interval in seconds (0 = manual only).
  final int syncIntervalSeconds;

  /// Maximum operations per sync batch.
  final int maxBatchSize;

  /// Retry policy settings.
  final RetryConfig retryConfig;

  @override
  String toString() =>
      'SyncConfig('
      'serverUrl: $serverUrl, '
      'dbId: $dbId, '
      'deviceId: $deviceId'
      ')';
}

/// Retry configuration for sync operations.
@immutable
class RetryConfig {
  /// Creates a retry configuration.
  const RetryConfig({
    this.maxRetries = 5,
    this.initialDelayMs = 1000,
    this.maxDelayMs = 30000,
    this.backoffMultiplier = 2.0,
  });

  /// Maximum retry attempts.
  final int maxRetries;

  /// Initial delay in milliseconds.
  final int initialDelayMs;

  /// Maximum delay in milliseconds.
  final int maxDelayMs;

  /// Backoff multiplier.
  final double backoffMultiplier;
}
