/// Compression Middleware Tests
import 'dart:io';

import 'package:entidb_sync_server/entidb_sync_server.dart';
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';

void main() {
  group('CompressionConfig', () {
    test('has sensible defaults', () {
      const config = CompressionConfig.defaultConfig;

      expect(config.minSizeBytes, 1024);
      expect(config.level, 6);
      expect(config.compressibleTypes, contains('application/cbor'));
      expect(config.compressibleTypes, contains('application/json'));
    });

    test('aggressive config has lower threshold', () {
      const config = CompressionConfig.aggressive;

      expect(config.minSizeBytes, 256);
      expect(config.level, 9);
    });

    test('fast config has higher threshold', () {
      const config = CompressionConfig.fast;

      expect(config.minSizeBytes, 2048);
      expect(config.level, 1);
    });
  });

  group('createCompressionMiddleware', () {
    late Handler handler;
    late Middleware middleware;

    setUp(() {
      middleware = createCompressionMiddleware();
    });

    test('compresses large JSON response when client accepts gzip', () async {
      // Create handler that returns large JSON
      final largeJson = '{"data": "${'x' * 2000}"}';
      handler = middleware(
        (_) async => Response.ok(
          largeJson,
          headers: {'content-type': 'application/json'},
        ),
      );

      final request = Request(
        'GET',
        Uri.parse('http://localhost/test'),
        headers: {'accept-encoding': 'gzip, deflate'},
      );

      final response = await handler(request);

      expect(response.headers['content-encoding'], 'gzip');
      expect(response.headers['vary'], 'Accept-Encoding');

      // Verify it's actually compressed (smaller than original)
      final body = await response.read().expand((x) => x).toList();
      expect(body.length, lessThan(largeJson.length));

      // Verify it decompresses correctly
      final decompressed = gzip.decode(body);
      expect(String.fromCharCodes(decompressed), largeJson);
    });

    test('compresses large CBOR response', () async {
      final largeCbor = List.filled(2000, 0x42);
      handler = middleware(
        (_) async => Response.ok(
          largeCbor,
          headers: {'content-type': 'application/cbor'},
        ),
      );

      final request = Request(
        'GET',
        Uri.parse('http://localhost/test'),
        headers: {'accept-encoding': 'gzip'},
      );

      final response = await handler(request);

      expect(response.headers['content-encoding'], 'gzip');
    });

    test('does not compress small responses', () async {
      const smallJson = '{"ok": true}';
      handler = middleware(
        (_) async => Response.ok(
          smallJson,
          headers: {'content-type': 'application/json'},
        ),
      );

      final request = Request(
        'GET',
        Uri.parse('http://localhost/test'),
        headers: {'accept-encoding': 'gzip'},
      );

      final response = await handler(request);

      expect(response.headers['content-encoding'], isNull);
    });

    test('does not compress if client does not accept gzip', () async {
      final largeJson = '{"data": "${'x' * 2000}"}';
      handler = middleware(
        (_) async => Response.ok(
          largeJson,
          headers: {'content-type': 'application/json'},
        ),
      );

      final request = Request(
        'GET',
        Uri.parse('http://localhost/test'),
        // No accept-encoding header
      );

      final response = await handler(request);

      expect(response.headers['content-encoding'], isNull);
    });

    test('does not compress non-compressible content types', () async {
      final largeData = List.filled(2000, 0x42);
      handler = middleware(
        (_) async => Response.ok(
          largeData,
          headers: {'content-type': 'image/png'}, // Not compressible
        ),
      );

      final request = Request(
        'GET',
        Uri.parse('http://localhost/test'),
        headers: {'accept-encoding': 'gzip'},
      );

      final response = await handler(request);

      expect(response.headers['content-encoding'], isNull);
    });

    test('does not compress already encoded responses', () async {
      final preCompressed = gzip.encode(List.filled(2000, 0x42));
      handler = middleware(
        (_) async => Response.ok(
          preCompressed,
          headers: {
            'content-type': 'application/cbor',
            'content-encoding': 'gzip',
          },
        ),
      );

      final request = Request(
        'GET',
        Uri.parse('http://localhost/test'),
        headers: {'accept-encoding': 'gzip'},
      );

      final response = await handler(request);

      // Should not double-compress
      expect(response.headers['content-encoding'], 'gzip');
      final body = await response.read().expand((x) => x).toList();
      expect(body, preCompressed);
    });
  });

  group('createDecompressionMiddleware', () {
    late Handler handler;
    late Middleware middleware;

    setUp(() {
      middleware = createDecompressionMiddleware();
    });

    test('decompresses gzip request body', () async {
      final originalData = '{"message": "hello world"}';
      final compressedData = gzip.encode(originalData.codeUnits);

      String? receivedBody;
      handler = middleware((request) async {
        receivedBody = await request.readAsString();
        return Response.ok('ok');
      });

      final request = Request(
        'POST',
        Uri.parse('http://localhost/test'),
        body: compressedData,
        headers: {'content-encoding': 'gzip'},
      );

      await handler(request);

      expect(receivedBody, originalData);
    });

    test('passes through uncompressed requests', () async {
      const originalData = '{"message": "hello world"}';

      String? receivedBody;
      handler = middleware((request) async {
        receivedBody = await request.readAsString();
        return Response.ok('ok');
      });

      final request = Request(
        'POST',
        Uri.parse('http://localhost/test'),
        body: originalData,
        // No content-encoding header
      );

      await handler(request);

      expect(receivedBody, originalData);
    });
  });

  group('CompressionStats', () {
    test('tracks compression statistics', () {
      final stats = CompressionStats();

      stats.totalOriginalBytes = 10000;
      stats.totalCompressedBytes = 3000;
      stats.responsesCompressed = 5;
      stats.responsesSkipped = 10;

      expect(stats.bytesSaved, 7000);
      expect(stats.averageRatio, 0.3);
    });

    test('resets all values', () {
      final stats = CompressionStats()
        ..totalOriginalBytes = 10000
        ..totalCompressedBytes = 3000
        ..responsesCompressed = 5
        ..responsesSkipped = 10;

      stats.reset();

      expect(stats.totalOriginalBytes, 0);
      expect(stats.totalCompressedBytes, 0);
      expect(stats.responsesCompressed, 0);
      expect(stats.responsesSkipped, 0);
      expect(stats.bytesSaved, 0);
      expect(stats.averageRatio, 1.0);
    });

    test('converts to map', () {
      final stats = CompressionStats()
        ..totalOriginalBytes = 1000
        ..totalCompressedBytes = 300
        ..responsesCompressed = 1
        ..responsesSkipped = 2;

      final map = stats.toMap();

      expect(map['totalOriginalBytes'], 1000);
      expect(map['totalCompressedBytes'], 300);
      expect(map['bytesSaved'], 700);
      expect(map['responsesCompressed'], 1);
      expect(map['responsesSkipped'], 2);
      expect(map['averageRatio'], 0.3);
    });
  });

  group('createCompressionMiddlewareWithStats', () {
    test('updates stats on compression', () async {
      final stats = CompressionStats();
      final middleware = createCompressionMiddlewareWithStats(stats: stats);

      final largeJson = '{"data": "${'x' * 2000}"}';
      final handler = middleware(
        (_) async => Response.ok(
          largeJson,
          headers: {'content-type': 'application/json'},
        ),
      );

      final request = Request(
        'GET',
        Uri.parse('http://localhost/test'),
        headers: {'accept-encoding': 'gzip'},
      );

      await handler(request);

      expect(stats.responsesCompressed, 1);
      expect(stats.totalOriginalBytes, greaterThan(0));
      expect(stats.totalCompressedBytes, greaterThan(0));
      expect(stats.bytesSaved, greaterThan(0));
    });

    test('updates stats when skipping', () async {
      final stats = CompressionStats();
      final middleware = createCompressionMiddlewareWithStats(stats: stats);

      const smallJson = '{"ok": true}';
      final handler = middleware(
        (_) async => Response.ok(
          smallJson,
          headers: {'content-type': 'application/json'},
        ),
      );

      final request = Request(
        'GET',
        Uri.parse('http://localhost/test'),
        headers: {'accept-encoding': 'gzip'},
      );

      await handler(request);

      expect(stats.responsesSkipped, 1);
      expect(stats.responsesCompressed, 0);
    });
  });
}
