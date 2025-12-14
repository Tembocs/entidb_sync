/// Logging Middleware
///
/// Request/response logging for the sync server.
library;

import 'package:logging/logging.dart';
import 'package:shelf/shelf.dart';

/// Creates logging middleware.
Middleware createLoggingMiddleware(Logger logger) {
  return (Handler innerHandler) {
    return (Request request) async {
      final stopwatch = Stopwatch()..start();

      Response response;
      try {
        response = await innerHandler(request);
      } catch (e, stack) {
        logger.severe(
            'Error handling ${request.method} ${request.url}', e, stack);
        rethrow;
      }

      stopwatch.stop();

      final logLevel = response.statusCode >= 400 ? Level.WARNING : Level.INFO;
      logger.log(
        logLevel,
        '${request.method} ${request.url} - ${response.statusCode} (${stopwatch.elapsedMilliseconds}ms)',
      );

      return response;
    };
  };
}
