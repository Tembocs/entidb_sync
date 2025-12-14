/// Metrics Middleware
///
/// Collects request/response metrics for Prometheus.
library;

import 'package:shelf/shelf.dart';

import '../metrics/prometheus_metrics.dart';

/// Creates middleware that collects request metrics.
///
/// Tracks request counts, durations, sizes, and errors.
Middleware createMetricsMiddleware() {
  return (Handler innerHandler) {
    return (Request request) async {
      final stopwatch = Stopwatch()..start();
      final endpoint = _normalizeEndpoint(request.url.path);
      final method = request.method;

      // Track request size
      final contentLength = request.contentLength;
      if (contentLength != null && contentLength > 0) {
        syncMetrics.requestSize.observe(
          contentLength.toDouble(),
          labels: {'endpoint': endpoint, 'method': method},
        );
      }

      try {
        final response = await innerHandler(request);

        stopwatch.stop();
        final durationSeconds = stopwatch.elapsedMicroseconds / 1000000;

        // Track request count
        syncMetrics.requestsTotal.inc(
          labels: {
            'endpoint': endpoint,
            'method': method,
            'status': '${response.statusCode}',
          },
        );

        // Track duration
        syncMetrics.requestDuration.observe(
          durationSeconds,
          labels: {'endpoint': endpoint, 'method': method},
        );

        // Track response size
        final responseLength = response.contentLength;
        if (responseLength != null && responseLength > 0) {
          syncMetrics.responseSize.observe(
            responseLength.toDouble(),
            labels: {'endpoint': endpoint, 'method': method},
          );
        }

        // Track errors (4xx and 5xx)
        if (response.statusCode >= 400) {
          syncMetrics.requestErrors.inc(
            labels: {
              'endpoint': endpoint,
              'method': method,
              'status': '${response.statusCode}',
            },
          );
        }

        return response;
      } catch (e) {
        stopwatch.stop();

        // Track error
        syncMetrics.requestErrors.inc(
          labels: {'endpoint': endpoint, 'method': method, 'status': '500'},
        );

        rethrow;
      }
    };
  };
}

/// Normalizes endpoint path for consistent labeling.
///
/// Replaces variable parts with placeholders.
String _normalizeEndpoint(String path) {
  // Remove leading slash if present
  if (path.startsWith('/')) {
    path = path.substring(1);
  }

  // Common sync endpoints
  if (path == 'v1/handshake') return '/v1/handshake';
  if (path == 'v1/pull') return '/v1/pull';
  if (path == 'v1/push') return '/v1/push';
  if (path == 'v1/events') return '/v1/events';
  if (path == 'v1/ws') return '/v1/ws';
  if (path == 'v1/stats') return '/v1/stats';
  if (path == 'v1/version') return '/v1/version';
  if (path == 'health') return '/health';
  if (path == 'metrics') return '/metrics';

  // Default: return as-is but with leading slash
  return '/$path';
}

/// Handler that exposes Prometheus metrics.
///
/// Returns metrics in Prometheus text format.
Response metricsHandler(Request request) {
  final metricsText = syncMetrics.collect();
  return Response.ok(
    metricsText,
    headers: {'Content-Type': 'text/plain; version=0.0.4; charset=utf-8'},
  );
}
