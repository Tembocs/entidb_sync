/// Rate Limit Middleware Tests
///
/// Tests for the rate limiting middleware.
library;

import 'dart:async';

import 'package:entidb_sync_server/entidb_sync_server.dart';
import 'package:test/test.dart';

void main() {
  group('RateLimitConfig', () {
    test('default configuration', () {
      const config = RateLimitConfig();

      expect(config.maxRequests, 100);
      expect(config.window, const Duration(minutes: 1));
      expect(config.includeHeaders, isTrue);
      expect(config.exemptPaths, ['/health']);
      expect(config.perClient, isTrue);
    });

    test('strict configuration', () {
      const config = RateLimitConfig.strict();

      expect(config.maxRequests, 30);
      expect(config.window, const Duration(minutes: 1));
    });

    test('lenient configuration', () {
      const config = RateLimitConfig.lenient();

      expect(config.maxRequests, 1000);
    });
  });

  group('TokenBucket', () {
    test('starts with max tokens', () {
      final bucket = TokenBucket(
        maxTokens: 10,
        refillInterval: const Duration(seconds: 1),
      );

      expect(bucket.availableTokens, 10);
    });

    test('consumes tokens', () {
      final bucket = TokenBucket(
        maxTokens: 5,
        refillInterval: const Duration(seconds: 1),
      );

      expect(bucket.tryConsume(), isTrue);
      expect(bucket.availableTokens, 4);

      expect(bucket.tryConsume(), isTrue);
      expect(bucket.availableTokens, 3);
    });

    test('denies when exhausted', () {
      final bucket = TokenBucket(
        maxTokens: 2,
        refillInterval: const Duration(hours: 1),
      );

      expect(bucket.tryConsume(), isTrue);
      expect(bucket.tryConsume(), isTrue);
      expect(bucket.tryConsume(), isFalse);
      expect(bucket.availableTokens, 0);
    });

    test('refills over time', () async {
      final bucket = TokenBucket(
        maxTokens: 5,
        refillInterval: const Duration(milliseconds: 20),
      );

      // Exhaust tokens
      for (var i = 0; i < 5; i++) {
        bucket.tryConsume();
      }
      expect(bucket.availableTokens, 0);

      // Wait for refill (longer wait to be safe on slow CI)
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(bucket.availableTokens, greaterThan(0));
    });

    test('timeUntilRefill returns remaining time', () {
      final bucket = TokenBucket(
        maxTokens: 5,
        refillInterval: const Duration(seconds: 10),
      );

      final time = bucket.timeUntilRefill;
      expect(time.inSeconds, lessThanOrEqualTo(10));
      expect(time.inSeconds, greaterThanOrEqualTo(0));
    });
  });

  group('RateLimiter', () {
    late RateLimiter limiter;

    setUp(() {
      limiter = RateLimiter(
        const RateLimitConfig(
          maxRequests: 3,
          window: const Duration(seconds: 1),
        ),
      );
    });

    tearDown(() {
      limiter.dispose();
    });

    test('allows requests within limit', () {
      expect(limiter.check('client1').allowed, isTrue);
      expect(limiter.check('client1').allowed, isTrue);
      expect(limiter.check('client1').allowed, isTrue);
    });

    test('denies requests over limit', () {
      limiter.check('client1');
      limiter.check('client1');
      limiter.check('client1');

      expect(limiter.check('client1').allowed, isFalse);
    });

    test('tracks clients separately', () {
      // Exhaust client1
      limiter.check('client1');
      limiter.check('client1');
      limiter.check('client1');

      // client2 still has tokens
      expect(limiter.check('client2').allowed, isTrue);
    });

    test('returns remaining count', () {
      final result1 = limiter.check('client1');
      expect(result1.remaining, 2);

      final result2 = limiter.check('client1');
      expect(result2.remaining, 1);
    });

    test('returns correct limit', () {
      final result = limiter.check('client1');
      expect(result.limit, 3);
    });
  });

  group('RateLimitResult', () {
    test('provides headers', () {
      const result = RateLimitResult(
        allowed: true,
        remaining: 5,
        limit: 10,
        resetIn: Duration(seconds: 30),
      );

      final headers = result.headers;
      expect(headers['X-RateLimit-Limit'], '10');
      expect(headers['X-RateLimit-Remaining'], '5');
      expect(headers['X-RateLimit-Reset'], '30');
    });
  });
}
