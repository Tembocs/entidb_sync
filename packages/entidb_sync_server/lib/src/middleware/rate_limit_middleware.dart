/// Rate Limiting Middleware
///
/// Token bucket rate limiting for sync API endpoints.
library;

import 'dart:async';

import 'package:entidb_sync_protocol/entidb_sync_protocol.dart';
import 'package:shelf/shelf.dart';

/// Configuration for rate limiting.
class RateLimitConfig {
  /// Maximum requests per time window.
  final int maxRequests;

  /// Time window duration.
  final Duration window;

  /// Whether to include rate limit headers in response.
  final bool includeHeaders;

  /// Paths exempt from rate limiting.
  final List<String> exemptPaths;

  /// Whether to rate limit by IP address (vs global).
  final bool perClient;

  const RateLimitConfig({
    this.maxRequests = 100,
    this.window = const Duration(minutes: 1),
    this.includeHeaders = true,
    this.exemptPaths = const ['/health'],
    this.perClient = true,
  });

  /// Creates a strict rate limit configuration.
  const RateLimitConfig.strict()
      : maxRequests = 30,
        window = const Duration(minutes: 1),
        includeHeaders = true,
        exemptPaths = const ['/health'],
        perClient = true;

  /// Creates a lenient rate limit configuration.
  const RateLimitConfig.lenient()
      : maxRequests = 1000,
        window = const Duration(minutes: 1),
        includeHeaders = true,
        exemptPaths = const ['/health'],
        perClient = true;
}

/// Token bucket for rate limiting.
class TokenBucket {
  final int maxTokens;
  final Duration refillInterval;

  int _tokens;
  DateTime _lastRefill;

  TokenBucket({
    required this.maxTokens,
    required this.refillInterval,
  })  : _tokens = maxTokens,
        _lastRefill = DateTime.now();

  /// Attempts to consume a token.
  ///
  /// Returns `true` if successful, `false` if rate limit exceeded.
  bool tryConsume() {
    _refill();

    if (_tokens > 0) {
      _tokens--;
      return true;
    }

    return false;
  }

  /// Gets the current number of available tokens.
  int get availableTokens {
    _refill();
    return _tokens;
  }

  /// Gets the time until next token refill.
  Duration get timeUntilRefill {
    final elapsed = DateTime.now().difference(_lastRefill);
    final remaining = refillInterval - elapsed;
    return remaining.isNegative ? Duration.zero : remaining;
  }

  /// Refills tokens based on elapsed time.
  void _refill() {
    final now = DateTime.now();
    final elapsed = now.difference(_lastRefill);

    if (elapsed >= refillInterval) {
      // Calculate how many refills have occurred
      final refills = elapsed.inMicroseconds ~/ refillInterval.inMicroseconds;
      _tokens = (_tokens + refills).clamp(0, maxTokens);
      _lastRefill =
          _lastRefill.add(refillInterval * refills);
    }
  }
}

/// Rate limiter that manages token buckets per client.
class RateLimiter {
  final RateLimitConfig config;

  /// Token buckets per client identifier.
  final Map<String, TokenBucket> _buckets = {};

  /// Global bucket for non-per-client limiting.
  late final TokenBucket _globalBucket;

  /// Timer for cleaning up stale buckets.
  Timer? _cleanupTimer;

  RateLimiter(this.config) {
    _globalBucket = TokenBucket(
      maxTokens: config.maxRequests,
      refillInterval: config.window,
    );

    // Clean up stale buckets every 5 minutes
    _cleanupTimer = Timer.periodic(
      const Duration(minutes: 5),
      (_) => _cleanup(),
    );
  }

  /// Checks if a request is allowed.
  ///
  /// Returns rate limit info including whether allowed and headers.
  RateLimitResult check(String clientId) {
    final bucket = config.perClient
        ? _getBucket(clientId)
        : _globalBucket;

    final allowed = bucket.tryConsume();

    return RateLimitResult(
      allowed: allowed,
      remaining: bucket.availableTokens,
      limit: config.maxRequests,
      resetIn: bucket.timeUntilRefill,
    );
  }

  /// Gets or creates a token bucket for a client.
  TokenBucket _getBucket(String clientId) {
    return _buckets.putIfAbsent(
      clientId,
      () => TokenBucket(
        maxTokens: config.maxRequests,
        refillInterval: config.window,
      ),
    );
  }

  /// Cleans up stale buckets.
  void _cleanup() {
    final threshold = DateTime.now().subtract(const Duration(minutes: 10));
    _buckets.removeWhere((_, bucket) {
      return bucket._lastRefill.isBefore(threshold);
    });
  }

  /// Disposes resources.
  void dispose() {
    _cleanupTimer?.cancel();
    _buckets.clear();
  }
}

/// Result of a rate limit check.
class RateLimitResult {
  /// Whether the request is allowed.
  final bool allowed;

  /// Remaining requests in current window.
  final int remaining;

  /// Maximum requests per window.
  final int limit;

  /// Time until rate limit resets.
  final Duration resetIn;

  const RateLimitResult({
    required this.allowed,
    required this.remaining,
    required this.limit,
    required this.resetIn,
  });

  /// Gets rate limit headers.
  Map<String, String> get headers => {
        'X-RateLimit-Limit': limit.toString(),
        'X-RateLimit-Remaining': remaining.toString(),
        'X-RateLimit-Reset': resetIn.inSeconds.toString(),
      };
}

/// Creates rate limiting middleware.
///
/// Limits requests per client using token bucket algorithm.
///
/// Usage:
/// ```dart
/// final config = RateLimitConfig(maxRequests: 100);
/// final handler = Pipeline()
///   .addMiddleware(createRateLimitMiddleware(config))
///   .addHandler(yourHandler);
/// ```
Middleware createRateLimitMiddleware([
  RateLimitConfig config = const RateLimitConfig(),
]) {
  final limiter = RateLimiter(config);

  return (Handler innerHandler) {
    return (Request request) async {
      // Check if path is exempt
      if (_isExempt(request.url.path, config.exemptPaths)) {
        return innerHandler(request);
      }

      // Get client identifier (IP or forwarded IP)
      final clientId = _getClientId(request);

      // Check rate limit
      final result = limiter.check(clientId);

      if (!result.allowed) {
        return _rateLimitExceededResponse(result, config.includeHeaders);
      }

      // Process request and add headers
      final response = await innerHandler(request);

      if (config.includeHeaders) {
        return response.change(
          headers: {...response.headers, ...result.headers},
        );
      }

      return response;
    };
  };
}

/// Extracts client identifier from request.
String _getClientId(Request request) {
  // Check for forwarded IP (behind proxy)
  final forwarded = request.headers['x-forwarded-for'];
  if (forwarded != null && forwarded.isNotEmpty) {
    return forwarded.split(',').first.trim();
  }

  // Check for real IP header
  final realIp = request.headers['x-real-ip'];
  if (realIp != null && realIp.isNotEmpty) {
    return realIp;
  }

  // Fallback to connection info (if available)
  // In shelf, we don't have direct access to connection info,
  // so we use a hash of available headers as fallback
  final userAgent = request.headers['user-agent'] ?? '';
  final host = request.headers['host'] ?? '';
  return '$userAgent:$host'.hashCode.toString();
}

/// Checks if a path is exempt from rate limiting.
bool _isExempt(String path, List<String> exemptPaths) {
  final normalizedPath = path.startsWith('/') ? path : '/$path';

  for (final exempt in exemptPaths) {
    if (normalizedPath == exempt || normalizedPath.startsWith('$exempt/')) {
      return true;
    }
  }

  return false;
}

/// Creates a rate limit exceeded response.
Response _rateLimitExceededResponse(
    RateLimitResult result, bool includeHeaders) {
  final error = ErrorResponse(
    code: SyncErrorCode.rateLimitExceeded,
    message: 'Rate limit exceeded. Try again in ${result.resetIn.inSeconds}s.',
    details: 'Limit: ${result.limit} requests per window',
  );

  return Response(
    429,
    body: error.toBytes(),
    headers: {
      'Content-Type': 'application/cbor',
      'Retry-After': result.resetIn.inSeconds.toString(),
      if (includeHeaders) ...result.headers,
    },
  );
}
