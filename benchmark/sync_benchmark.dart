/// EntiDB Sync Performance Benchmarks
///
/// Measures throughput, latency, and memory usage for sync operations.
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:entidb_sync_protocol/entidb_sync_protocol.dart';
import 'package:entidb_sync_server/entidb_sync_server.dart';

/// Benchmark configuration.
class BenchmarkConfig {
  /// Number of operations to generate.
  final int operationCount;

  /// Size of entity CBOR payload in bytes.
  final int entitySize;

  /// Number of warmup iterations.
  final int warmupIterations;

  /// Number of benchmark iterations.
  final int benchmarkIterations;

  /// Creates benchmark configuration.
  const BenchmarkConfig({
    this.operationCount = 1000,
    this.entitySize = 1024,
    this.warmupIterations = 3,
    this.benchmarkIterations = 10,
  });

  /// Quick benchmark for testing.
  static const quick = BenchmarkConfig(
    operationCount: 100,
    entitySize: 256,
    warmupIterations: 1,
    benchmarkIterations: 3,
  );

  /// Standard benchmark for development.
  static const standard = BenchmarkConfig(
    operationCount: 1000,
    entitySize: 1024,
    warmupIterations: 3,
    benchmarkIterations: 10,
  );

  /// Heavy benchmark for stress testing.
  static const heavy = BenchmarkConfig(
    operationCount: 10000,
    entitySize: 4096,
    warmupIterations: 5,
    benchmarkIterations: 20,
  );
}

/// Result of a single benchmark run.
class BenchmarkResult {
  /// Name of the benchmark.
  final String name;

  /// Total operations processed.
  final int operationCount;

  /// Total time in milliseconds.
  final double totalTimeMs;

  /// Operations per second.
  double get opsPerSecond => operationCount / (totalTimeMs / 1000);

  /// Average latency per operation in microseconds.
  double get avgLatencyUs => (totalTimeMs * 1000) / operationCount;

  /// Minimum time of all iterations.
  final double minTimeMs;

  /// Maximum time of all iterations.
  final double maxTimeMs;

  /// Creates a benchmark result.
  const BenchmarkResult({
    required this.name,
    required this.operationCount,
    required this.totalTimeMs,
    required this.minTimeMs,
    required this.maxTimeMs,
  });

  @override
  String toString() {
    return '''
$name:
  Operations: $operationCount
  Total Time: ${totalTimeMs.toStringAsFixed(2)} ms
  Throughput: ${opsPerSecond.toStringAsFixed(0)} ops/sec
  Avg Latency: ${avgLatencyUs.toStringAsFixed(2)} μs
  Min/Max: ${minTimeMs.toStringAsFixed(2)} / ${maxTimeMs.toStringAsFixed(2)} ms
''';
  }
}

/// Runs all benchmarks and reports results.
class BenchmarkRunner {
  /// Configuration.
  final BenchmarkConfig config;

  /// Generated test operations.
  late List<SyncOperation> _operations;

  /// Sync service for testing.
  late SyncService _syncService;

  /// Creates a benchmark runner.
  BenchmarkRunner({this.config = BenchmarkConfig.standard});

  /// Runs all benchmarks.
  Future<List<BenchmarkResult>> runAll() async {
    print('EntiDB Sync Performance Benchmarks');
    print('=' * 50);
    print('Configuration:');
    print('  Operations: ${config.operationCount}');
    print('  Entity Size: ${config.entitySize} bytes');
    print('  Warmup Iterations: ${config.warmupIterations}');
    print('  Benchmark Iterations: ${config.benchmarkIterations}');
    print('');

    _setup();

    final results = <BenchmarkResult>[];

    results.add(await _benchmarkCborSerialization());
    results.add(await _benchmarkCborDeserialization());
    results.add(await _benchmarkPush());
    results.add(await _benchmarkPull());
    results.add(await _benchmarkPullFiltered());

    print('');
    print('Summary');
    print('=' * 50);
    for (final result in results) {
      print(result);
    }

    return results;
  }

  void _setup() {
    print('Setting up benchmark data...');

    // Generate test operations
    _operations = List.generate(
      config.operationCount,
      (i) => SyncOperation(
        opId: i + 1,
        dbId: 'bench-db',
        deviceId: 'bench-device',
        collection: 'collection-${i % 10}', // 10 collections
        entityId: 'entity-$i',
        opType: OperationType.upsert,
        entityVersion: 1,
        entityCbor: _generateEntityData(i),
        timestampMs: DateTime.now().millisecondsSinceEpoch,
      ),
    );

    // Create sync service
    _syncService = SyncService();

    print('Generated ${_operations.length} operations');
    print('');
  }

  Uint8List _generateEntityData(int seed) {
    // Generate pseudo-random but deterministic data
    final data = Uint8List(config.entitySize);
    for (var i = 0; i < config.entitySize; i++) {
      data[i] = (seed + i) % 256;
    }
    return data;
  }

  Future<BenchmarkResult> _benchmarkCborSerialization() async {
    print('Running: CBOR Serialization');

    final times = <double>[];

    // Warmup
    for (var i = 0; i < config.warmupIterations; i++) {
      for (final op in _operations) {
        op.toBytes();
      }
    }

    // Benchmark
    for (var iter = 0; iter < config.benchmarkIterations; iter++) {
      final stopwatch = Stopwatch()..start();

      for (final op in _operations) {
        op.toBytes();
      }

      stopwatch.stop();
      times.add(stopwatch.elapsedMicroseconds / 1000.0);
    }

    return BenchmarkResult(
      name: 'CBOR Serialization',
      operationCount: config.operationCount,
      totalTimeMs: times.reduce((a, b) => a + b) / times.length,
      minTimeMs: times.reduce((a, b) => a < b ? a : b),
      maxTimeMs: times.reduce((a, b) => a > b ? a : b),
    );
  }

  Future<BenchmarkResult> _benchmarkCborDeserialization() async {
    print('Running: CBOR Deserialization');

    // Pre-serialize operations
    final serialized = _operations.map((op) => op.toBytes()).toList();

    final times = <double>[];

    // Warmup
    for (var i = 0; i < config.warmupIterations; i++) {
      for (final bytes in serialized) {
        SyncOperation.fromBytes(bytes);
      }
    }

    // Benchmark
    for (var iter = 0; iter < config.benchmarkIterations; iter++) {
      final stopwatch = Stopwatch()..start();

      for (final bytes in serialized) {
        SyncOperation.fromBytes(bytes);
      }

      stopwatch.stop();
      times.add(stopwatch.elapsedMicroseconds / 1000.0);
    }

    return BenchmarkResult(
      name: 'CBOR Deserialization',
      operationCount: config.operationCount,
      totalTimeMs: times.reduce((a, b) => a + b) / times.length,
      minTimeMs: times.reduce((a, b) => a < b ? a : b),
      maxTimeMs: times.reduce((a, b) => a > b ? a : b),
    );
  }

  Future<BenchmarkResult> _benchmarkPush() async {
    print('Running: Push Operations');

    final times = <double>[];

    // Warmup
    for (var i = 0; i < config.warmupIterations; i++) {
      _syncService = SyncService(); // Fresh service
      await _syncService.handlePush(
        PushRequest(
            dbId: 'bench-db', deviceId: 'bench-device', ops: _operations),
      );
    }

    // Benchmark
    for (var iter = 0; iter < config.benchmarkIterations; iter++) {
      _syncService = SyncService(); // Fresh service

      final stopwatch = Stopwatch()..start();

      await _syncService.handlePush(
        PushRequest(
            dbId: 'bench-db', deviceId: 'bench-device', ops: _operations),
      );

      stopwatch.stop();
      times.add(stopwatch.elapsedMicroseconds / 1000.0);
    }

    return BenchmarkResult(
      name: 'Push Operations',
      operationCount: config.operationCount,
      totalTimeMs: times.reduce((a, b) => a + b) / times.length,
      minTimeMs: times.reduce((a, b) => a < b ? a : b),
      maxTimeMs: times.reduce((a, b) => a > b ? a : b),
    );
  }

  Future<BenchmarkResult> _benchmarkPull() async {
    print('Running: Pull Operations');

    // Populate service with data
    _syncService = SyncService();
    await _syncService.handlePush(
      PushRequest(dbId: 'bench-db', deviceId: 'bench-device', ops: _operations),
    );

    final times = <double>[];

    // Warmup
    for (var i = 0; i < config.warmupIterations; i++) {
      await _syncService.handlePull(
        PullRequest(
            dbId: 'bench-db', sinceCursor: 0, limit: config.operationCount),
      );
    }

    // Benchmark
    for (var iter = 0; iter < config.benchmarkIterations; iter++) {
      final stopwatch = Stopwatch()..start();

      await _syncService.handlePull(
        PullRequest(
            dbId: 'bench-db', sinceCursor: 0, limit: config.operationCount),
      );

      stopwatch.stop();
      times.add(stopwatch.elapsedMicroseconds / 1000.0);
    }

    return BenchmarkResult(
      name: 'Pull Operations (all)',
      operationCount: config.operationCount,
      totalTimeMs: times.reduce((a, b) => a + b) / times.length,
      minTimeMs: times.reduce((a, b) => a < b ? a : b),
      maxTimeMs: times.reduce((a, b) => a > b ? a : b),
    );
  }

  Future<BenchmarkResult> _benchmarkPullFiltered() async {
    print('Running: Pull Operations (filtered by collection)');

    // Populate service with data
    _syncService = SyncService();
    await _syncService.handlePush(
      PushRequest(dbId: 'bench-db', deviceId: 'bench-device', ops: _operations),
    );

    final times = <double>[];
    const collections = ['collection-0', 'collection-1'];

    // Warmup
    for (var i = 0; i < config.warmupIterations; i++) {
      await _syncService.handlePull(
        PullRequest(
          dbId: 'bench-db',
          sinceCursor: 0,
          limit: config.operationCount,
          collections: collections,
        ),
      );
    }

    // Benchmark
    for (var iter = 0; iter < config.benchmarkIterations; iter++) {
      final stopwatch = Stopwatch()..start();

      await _syncService.handlePull(
        PullRequest(
          dbId: 'bench-db',
          sinceCursor: 0,
          limit: config.operationCount,
          collections: collections,
        ),
      );

      stopwatch.stop();
      times.add(stopwatch.elapsedMicroseconds / 1000.0);
    }

    // Approximate filtered count (2 out of 10 collections)
    final expectedCount = config.operationCount ~/ 5;

    return BenchmarkResult(
      name: 'Pull Operations (filtered)',
      operationCount: expectedCount,
      totalTimeMs: times.reduce((a, b) => a + b) / times.length,
      minTimeMs: times.reduce((a, b) => a < b ? a : b),
      maxTimeMs: times.reduce((a, b) => a > b ? a : b),
    );
  }
}

/// Main entry point for running benchmarks.
Future<void> main(List<String> args) async {
  final config = args.contains('--quick')
      ? BenchmarkConfig.quick
      : args.contains('--heavy')
          ? BenchmarkConfig.heavy
          : BenchmarkConfig.standard;

  final runner = BenchmarkRunner(config: config);
  await runner.runAll();

  exit(0);
}
