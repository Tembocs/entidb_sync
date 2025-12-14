# Performance Benchmarks

This directory contains performance benchmarks for the EntiDB Sync system.

## Running Benchmarks

```bash
cd benchmark
dart pub get
dart run sync_benchmark.dart
```

## Benchmark Modes

- **Quick** (for testing): `dart run sync_benchmark.dart --quick`
  - 100 operations, 256 byte entities, 1 warmup, 3 iterations
  
- **Standard** (default): `dart run sync_benchmark.dart`
  - 1000 operations, 1KB entities, 3 warmup, 10 iterations
  
- **Heavy** (stress test): `dart run sync_benchmark.dart --heavy`
  - 10000 operations, 4KB entities, 5 warmup, 20 iterations

## Measured Metrics

1. **CBOR Serialization** - Time to serialize sync operations to CBOR bytes
2. **CBOR Deserialization** - Time to deserialize CBOR bytes to sync operations
3. **Push Operations** - Time to push operations to the server
4. **Pull Operations (all)** - Time to pull all operations from server
5. **Pull Operations (filtered)** - Time to pull with collection filter

## Sample Output

```
EntiDB Sync Performance Benchmarks
==================================================
Configuration:
  Operations: 1000
  Entity Size: 1024 bytes
  Warmup Iterations: 3
  Benchmark Iterations: 10

Setting up benchmark data...
Generated 1000 operations

Running: CBOR Serialization
Running: CBOR Deserialization
Running: Push Operations
Running: Pull Operations
Running: Pull Operations (filtered by collection)

Summary
==================================================
CBOR Serialization:
  Operations: 1000
  Total Time: 12.50 ms
  Throughput: 80000 ops/sec
  Avg Latency: 12.50 μs
  Min/Max: 11.20 / 14.30 ms

...
```

## Interpreting Results

- **Throughput (ops/sec)**: Higher is better. Indicates how many operations per second can be processed.
- **Avg Latency (μs)**: Lower is better. Average time per operation.
- **Min/Max**: Helps identify variance. Large gaps may indicate GC pauses or system load.

## Tips for Accurate Benchmarks

1. Close other applications to reduce noise
2. Run multiple times and compare results
3. Use `--heavy` mode for production capacity planning
4. Monitor CPU and memory during heavy benchmarks
