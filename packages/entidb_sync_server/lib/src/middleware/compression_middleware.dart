/// Compression Middleware
///
/// Provides gzip compression support for HTTP responses.
library;

import 'dart:io';

import 'package:shelf/shelf.dart';

/// Configuration for compression middleware.
class CompressionConfig {
  /// Creates compression configuration.
  const CompressionConfig({
    this.minSizeBytes = 1024, // 1KB minimum
    this.compressibleTypes = const [
      'application/cbor',
      'application/json',
      'text/plain',
      'text/event-stream',
    ],
    this.level = 6, // Default zlib level (balanced)
  });

  /// Default configuration.
  static const CompressionConfig defaultConfig = CompressionConfig();

  /// Aggressive compression for bandwidth-constrained environments.
  static const CompressionConfig aggressive = CompressionConfig(
    minSizeBytes: 256,
    level: 9,
  );

  /// Fast compression for low-latency requirements.
  static const CompressionConfig fast = CompressionConfig(
    minSizeBytes: 2048,
    level: 1,
  );

  /// Minimum response size in bytes to trigger compression.
  /// Responses smaller than this won't be compressed (overhead not worth it).
  final int minSizeBytes;

  /// Content types that should be compressed.
  /// CBOR and JSON are highly compressible.
  final List<String> compressibleTypes;

  /// Compression level (1-9). Higher = better compression, slower.
  final int level;
}

/// Creates compression middleware.
///
/// Compresses responses with gzip when:
/// - Client sends `Accept-Encoding: gzip`
/// - Response content-type is compressible
/// - Response size exceeds minimum threshold
///
/// Example:
/// ```dart
/// final handler = Pipeline()
///     .addMiddleware(createCompressionMiddleware())
///     .addHandler(router);
/// ```
Middleware createCompressionMiddleware({
  CompressionConfig config = CompressionConfig.defaultConfig,
}) {
  return (Handler innerHandler) {
    return (Request request) async {
      final response = await innerHandler(request);

      // Check if client accepts gzip
      final acceptEncoding = request.headers['accept-encoding'] ?? '';
      if (!acceptEncoding.contains('gzip')) {
        return response;
      }

      // Check if already encoded
      if (response.headers.containsKey('content-encoding')) {
        return response;
      }

      // Check content type
      final contentType = response.headers['content-type'] ?? '';
      final isCompressible = config.compressibleTypes.any(
        (type) => contentType.startsWith(type),
      );

      if (!isCompressible) {
        return response;
      }

      // Read body
      final body = await response.read().expand((x) => x).toList();

      // Check size threshold
      if (body.length < config.minSizeBytes) {
        return response.change(body: body);
      }

      // Compress with gzip
      final compressed = gzip.encode(body);

      // Only use compression if it's actually smaller
      if (compressed.length >= body.length) {
        return response.change(body: body);
      }

      // Return compressed response
      return response.change(
        body: compressed,
        headers: {
          ...response.headers,
          'content-encoding': 'gzip',
          'content-length': compressed.length.toString(),
          'vary': 'Accept-Encoding',
        },
      );
    };
  };
}

/// Creates decompression middleware for handling compressed requests.
///
/// Decompresses incoming requests with `Content-Encoding: gzip`.
///
/// Example:
/// ```dart
/// final handler = Pipeline()
///     .addMiddleware(createDecompressionMiddleware())
///     .addHandler(router);
/// ```
Middleware createDecompressionMiddleware() {
  return (Handler innerHandler) {
    return (Request request) async {
      final contentEncoding = request.headers['content-encoding'];

      if (contentEncoding == null || !contentEncoding.contains('gzip')) {
        return innerHandler(request);
      }

      // Read and decompress body
      final compressedBody = await request.read().expand((x) => x).toList();
      final decompressedBody = gzip.decode(compressedBody);

      // Create new request with decompressed body
      final newRequest = request.change(
        body: decompressedBody,
        headers: {...request.headers}..remove('content-encoding'),
      );

      return innerHandler(newRequest);
    };
  };
}

/// Compression statistics for monitoring.
class CompressionStats {
  /// Total bytes before compression.
  int totalOriginalBytes = 0;

  /// Total bytes after compression.
  int totalCompressedBytes = 0;

  /// Number of responses compressed.
  int responsesCompressed = 0;

  /// Number of responses skipped (too small, not compressible, etc).
  int responsesSkipped = 0;

  /// Average compression ratio (compressed / original).
  double get averageRatio =>
      totalOriginalBytes > 0 ? totalCompressedBytes / totalOriginalBytes : 1.0;

  /// Bytes saved by compression.
  int get bytesSaved => totalOriginalBytes - totalCompressedBytes;

  /// Resets all statistics.
  void reset() {
    totalOriginalBytes = 0;
    totalCompressedBytes = 0;
    responsesCompressed = 0;
    responsesSkipped = 0;
  }

  /// Returns stats as a map for logging/monitoring.
  Map<String, dynamic> toMap() => {
    'totalOriginalBytes': totalOriginalBytes,
    'totalCompressedBytes': totalCompressedBytes,
    'bytesSaved': bytesSaved,
    'responsesCompressed': responsesCompressed,
    'responsesSkipped': responsesSkipped,
    'averageRatio': averageRatio,
  };

  @override
  String toString() =>
      'CompressionStats(saved: $bytesSaved bytes, '
      'ratio: ${(averageRatio * 100).toStringAsFixed(1)}%, '
      'compressed: $responsesCompressed, skipped: $responsesSkipped)';
}

/// Creates compression middleware with statistics tracking.
///
/// Example:
/// ```dart
/// final stats = CompressionStats();
/// final handler = Pipeline()
///     .addMiddleware(createCompressionMiddlewareWithStats(stats: stats))
///     .addHandler(router);
///
/// // Later: check stats
/// print(stats);
/// ```
Middleware createCompressionMiddlewareWithStats({
  required CompressionStats stats,
  CompressionConfig config = CompressionConfig.defaultConfig,
}) {
  return (Handler innerHandler) {
    return (Request request) async {
      final response = await innerHandler(request);

      // Check if client accepts gzip
      final acceptEncoding = request.headers['accept-encoding'] ?? '';
      if (!acceptEncoding.contains('gzip')) {
        stats.responsesSkipped++;
        return response;
      }

      // Check if already encoded
      if (response.headers.containsKey('content-encoding')) {
        stats.responsesSkipped++;
        return response;
      }

      // Check content type
      final contentType = response.headers['content-type'] ?? '';
      final isCompressible = config.compressibleTypes.any(
        (type) => contentType.startsWith(type),
      );

      if (!isCompressible) {
        stats.responsesSkipped++;
        return response;
      }

      // Read body
      final body = await response.read().expand((x) => x).toList();

      // Check size threshold
      if (body.length < config.minSizeBytes) {
        stats.responsesSkipped++;
        return response.change(body: body);
      }

      // Compress with gzip
      final compressed = gzip.encode(body);

      // Only use compression if it's actually smaller
      if (compressed.length >= body.length) {
        stats.responsesSkipped++;
        return response.change(body: body);
      }

      // Update stats
      stats.totalOriginalBytes += body.length;
      stats.totalCompressedBytes += compressed.length;
      stats.responsesCompressed++;

      // Return compressed response
      return response.change(
        body: compressed,
        headers: {
          ...response.headers,
          'content-encoding': 'gzip',
          'content-length': compressed.length.toString(),
          'vary': 'Accept-Encoding',
        },
      );
    };
  };
}
