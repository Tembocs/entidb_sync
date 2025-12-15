/// Server Configuration
///
/// Configuration model for the sync server.
library;

import 'dart:io';

/// Configuration for the sync server.
class ServerConfig {
  /// Creates a server configuration.
  const ServerConfig({
    this.host = '0.0.0.0',
    this.port = 8080,
    this.dbPath = 'sync_server.db',
    this.jwtSecret = 'change-me-in-production',
    this.enableCors = true,
    this.corsAllowedOrigins = const ['*'],
    this.maxPullLimit = 1000,
    this.maxPushBatchSize = 100,
    this.logLevel = 'INFO',
  });

  /// Creates configuration from environment variables.
  factory ServerConfig.fromEnvironment() {
    final env = Platform.environment;
    return ServerConfig(
      host: env['HOST'] ?? '0.0.0.0',
      port: int.parse(env['PORT'] ?? '8080'),
      dbPath: env['DB_PATH'] ?? 'sync_server.db',
      jwtSecret: env['JWT_SECRET'] ?? 'change-me-in-production',
      enableCors: env['ENABLE_CORS']?.toLowerCase() != 'false',
      corsAllowedOrigins: env['CORS_ALLOWED_ORIGINS']?.split(',') ?? ['*'],
      maxPullLimit: int.parse(env['MAX_PULL_LIMIT'] ?? '1000'),
      maxPushBatchSize: int.parse(env['MAX_PUSH_BATCH_SIZE'] ?? '100'),
      logLevel: env['LOG_LEVEL'] ?? 'INFO',
    );
  }

  /// Host address to bind to.
  final String host;

  /// Port to listen on.
  final int port;

  /// Path to the EntiDB database file.
  final String dbPath;

  /// JWT secret for token validation.
  final String jwtSecret;

  /// Whether to enable CORS headers.
  final bool enableCors;

  /// Allowed origins for CORS.
  final List<String> corsAllowedOrigins;

  /// Maximum operations per pull request.
  final int maxPullLimit;

  /// Maximum operations per push request.
  final int maxPushBatchSize;

  /// Log level (INFO, WARNING, SEVERE, etc.)
  final String logLevel;

  @override
  String toString() =>
      'ServerConfig(host: $host, port: $port, dbPath: $dbPath)';
}
