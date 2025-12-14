#!/usr/bin/env dart

import 'dart:io';

import 'package:entidb_sync_server/entidb_sync_server.dart';
import 'package:logging/logging.dart';
import 'package:shelf/shelf.dart' as shelf;
import 'package:shelf/shelf_io.dart' as io;

void main(List<String> arguments) async {
  // Configure logging
  _setupLogging();
  final log = Logger('Server');

  // Load configuration
  final config = ServerConfig.fromEnvironment();
  log.info('Starting EntiDB Sync Server with config: $config');

  // Create sync service
  final syncService = SyncService();

  // Create router
  final router = createSyncRouter(syncService);

  // Configure JWT authentication
  final jwtConfig = JwtAuthConfig(
    secret: config.jwtSecret,
    publicPaths: ['/health', '/v1/version'],
  );

  // Configure rate limiting
  final rateLimitConfig = RateLimitConfig(
    maxRequests: 100,
    window: const Duration(minutes: 1),
    exemptPaths: ['/health'],
  );

  // Build handler pipeline with all middleware
  final handler = const shelf.Pipeline()
      .addMiddleware(createLoggingMiddleware(log))
      .addMiddleware(createCorsMiddleware(
        allowedOrigins: config.corsAllowedOrigins,
      ))
      .addMiddleware(createRateLimitMiddleware(rateLimitConfig))
      .addMiddleware(createJwtAuthMiddleware(jwtConfig))
      .addHandler(router.call);

  // Start server
  final server = await io.serve(handler, config.host, config.port);

  log.info('Server listening on http://${server.address.host}:${server.port}');
  log.info('Endpoints:');
  log.info('  GET  /health       - Health check (public)');
  log.info('  GET  /v1/version   - Protocol version (public)');
  log.info('  POST /v1/handshake - Client handshake (auth required)');
  log.info('  POST /v1/pull      - Pull operations (auth required)');
  log.info('  POST /v1/push      - Push operations (auth required)');
  log.info('  GET  /v1/stats     - Server statistics (auth required)');
  log.info('');
  log.info('Security:');
  log.info('  JWT Auth: enabled (set JWT_SECRET env var)');
  log.info('  Rate Limit: ${rateLimitConfig.maxRequests} req/min');

  // Handle shutdown signals
  ProcessSignal.sigint.watch().listen((_) async {
    log.info('Shutting down...');
    await server.close();
    exit(0);
  });
}

void _setupLogging() {
  Logger.root.level = Level.INFO;
  Logger.root.onRecord.listen((record) {
    final time = record.time.toIso8601String().substring(11, 23);
    print(
        '$time [${record.level.name}] ${record.loggerName}: ${record.message}');
    if (record.error != null) {
      print('  Error: ${record.error}');
    }
    if (record.stackTrace != null) {
      print('  Stack: ${record.stackTrace}');
    }
  });
}
