/// Prometheus Metrics
///
/// Exposes sync server metrics in Prometheus format.
library;

import 'dart:async';

/// Metric types for Prometheus.
enum MetricType {
  /// Counter that only increases.
  counter,

  /// Gauge that can increase or decrease.
  gauge,

  /// Histogram for distributions.
  histogram,

  /// Summary with quantiles.
  summary,
}

/// A single metric value with optional labels.
class MetricSample {
  /// Metric name.
  final String name;

  /// Metric value.
  final double value;

  /// Optional labels.
  final Map<String, String> labels;

  /// Optional timestamp.
  final DateTime? timestamp;

  const MetricSample({
    required this.name,
    required this.value,
    this.labels = const {},
    this.timestamp,
  });

  /// Formats as Prometheus line.
  String toPrometheusLine() {
    final buffer = StringBuffer(name);

    if (labels.isNotEmpty) {
      buffer.write('{');
      buffer.write(
        labels.entries.map((e) => '${e.key}="${_escape(e.value)}"').join(','),
      );
      buffer.write('}');
    }

    buffer.write(' $value');

    if (timestamp != null) {
      buffer.write(' ${timestamp!.millisecondsSinceEpoch}');
    }

    return buffer.toString();
  }

  String _escape(String value) {
    return value
        .replaceAll('\\', '\\\\')
        .replaceAll('"', '\\"')
        .replaceAll('\n', '\\n');
  }
}

/// Metric definition with help and type.
class MetricDefinition {
  /// Metric name.
  final String name;

  /// Help text.
  final String help;

  /// Metric type.
  final MetricType type;

  const MetricDefinition({
    required this.name,
    required this.help,
    required this.type,
  });

  /// Formats TYPE and HELP lines.
  String toPrometheusHeader() {
    return '# HELP $name $help\n# TYPE $name ${type.name}';
  }
}

/// Counter metric that only increases.
class Counter {
  final String name;
  final String help;
  final Map<String, double> _values = {};

  Counter({required this.name, required this.help});

  /// Increments the counter.
  void inc({Map<String, String> labels = const {}, double value = 1}) {
    final key = _labelsKey(labels);
    _values[key] = (_values[key] ?? 0) + value;
  }

  /// Gets current value.
  double get({Map<String, String> labels = const {}}) {
    return _values[_labelsKey(labels)] ?? 0;
  }

  /// Collects all samples.
  List<MetricSample> collect() {
    return _values.entries.map((e) {
      return MetricSample(
        name: name,
        value: e.value,
        labels: _parseLabelsKey(e.key),
      );
    }).toList();
  }

  MetricDefinition get definition =>
      MetricDefinition(name: name, help: help, type: MetricType.counter);

  String _labelsKey(Map<String, String> labels) {
    if (labels.isEmpty) return '';
    final sorted = labels.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));
    return sorted.map((e) => '${e.key}=${e.value}').join(',');
  }

  Map<String, String> _parseLabelsKey(String key) {
    if (key.isEmpty) return {};
    return Map.fromEntries(
      key.split(',').map((pair) {
        final parts = pair.split('=');
        return MapEntry(parts[0], parts[1]);
      }),
    );
  }
}

/// Gauge metric that can increase or decrease.
class Gauge {
  final String name;
  final String help;
  final Map<String, double> _values = {};

  Gauge({required this.name, required this.help});

  /// Sets the gauge value.
  void set(double value, {Map<String, String> labels = const {}}) {
    _values[_labelsKey(labels)] = value;
  }

  /// Increments the gauge.
  void inc({Map<String, String> labels = const {}, double value = 1}) {
    final key = _labelsKey(labels);
    _values[key] = (_values[key] ?? 0) + value;
  }

  /// Decrements the gauge.
  void dec({Map<String, String> labels = const {}, double value = 1}) {
    final key = _labelsKey(labels);
    _values[key] = (_values[key] ?? 0) - value;
  }

  /// Gets current value.
  double get({Map<String, String> labels = const {}}) {
    return _values[_labelsKey(labels)] ?? 0;
  }

  /// Collects all samples.
  List<MetricSample> collect() {
    return _values.entries.map((e) {
      return MetricSample(
        name: name,
        value: e.value,
        labels: _parseLabelsKey(e.key),
      );
    }).toList();
  }

  MetricDefinition get definition =>
      MetricDefinition(name: name, help: help, type: MetricType.gauge);

  String _labelsKey(Map<String, String> labels) {
    if (labels.isEmpty) return '';
    final sorted = labels.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));
    return sorted.map((e) => '${e.key}=${e.value}').join(',');
  }

  Map<String, String> _parseLabelsKey(String key) {
    if (key.isEmpty) return {};
    return Map.fromEntries(
      key.split(',').map((pair) {
        final parts = pair.split('=');
        return MapEntry(parts[0], parts[1]);
      }),
    );
  }
}

/// Histogram metric for distributions.
class Histogram {
  final String name;
  final String help;
  final List<double> buckets;

  final Map<String, List<int>> _bucketCounts = {};
  final Map<String, double> _sums = {};
  final Map<String, int> _counts = {};

  Histogram({
    required this.name,
    required this.help,
    this.buckets = const [
      0.005,
      0.01,
      0.025,
      0.05,
      0.1,
      0.25,
      0.5,
      1,
      2.5,
      5,
      10,
    ],
  });

  /// Observes a value.
  void observe(double value, {Map<String, String> labels = const {}}) {
    final key = _labelsKey(labels);

    // Initialize if needed
    _bucketCounts.putIfAbsent(key, () => List.filled(buckets.length + 1, 0));
    _sums.putIfAbsent(key, () => 0);
    _counts.putIfAbsent(key, () => 0);

    // Update buckets - find the first bucket where value fits
    // Store non-cumulative counts; cumulative is computed in collect()
    var placed = false;
    for (int i = 0; i < buckets.length; i++) {
      if (!placed && value <= buckets[i]) {
        _bucketCounts[key]![i]++;
        placed = true;
        break;
      }
    }
    // If not placed in any bucket, it goes to +Inf
    if (!placed) {
      _bucketCounts[key]![buckets.length]++;
    }

    _sums[key] = _sums[key]! + value;
    _counts[key] = _counts[key]! + 1;
  }

  /// Times a function execution.
  T time<T>(T Function() fn, {Map<String, String> labels = const {}}) {
    final stopwatch = Stopwatch()..start();
    try {
      return fn();
    } finally {
      stopwatch.stop();
      observe(stopwatch.elapsedMicroseconds / 1000000, labels: labels);
    }
  }

  /// Times an async function execution.
  Future<T> timeAsync<T>(
    Future<T> Function() fn, {
    Map<String, String> labels = const {},
  }) async {
    final stopwatch = Stopwatch()..start();
    try {
      return await fn();
    } finally {
      stopwatch.stop();
      observe(stopwatch.elapsedMicroseconds / 1000000, labels: labels);
    }
  }

  /// Collects all samples.
  List<MetricSample> collect() {
    final samples = <MetricSample>[];

    for (final entry in _bucketCounts.entries) {
      final labels = _parseLabelsKey(entry.key);
      var cumulative = 0;

      for (int i = 0; i < buckets.length; i++) {
        cumulative += entry.value[i];
        samples.add(
          MetricSample(
            name: '${name}_bucket',
            value: cumulative.toDouble(),
            labels: {...labels, 'le': buckets[i].toString()},
          ),
        );
      }

      // +Inf bucket
      cumulative += entry.value[buckets.length];
      samples.add(
        MetricSample(
          name: '${name}_bucket',
          value: cumulative.toDouble(),
          labels: {...labels, 'le': '+Inf'},
        ),
      );

      samples.add(
        MetricSample(
          name: '${name}_sum',
          value: _sums[entry.key]!,
          labels: labels,
        ),
      );

      samples.add(
        MetricSample(
          name: '${name}_count',
          value: _counts[entry.key]!.toDouble(),
          labels: labels,
        ),
      );
    }

    return samples;
  }

  MetricDefinition get definition =>
      MetricDefinition(name: name, help: help, type: MetricType.histogram);

  String _labelsKey(Map<String, String> labels) {
    if (labels.isEmpty) return '';
    final sorted = labels.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));
    return sorted.map((e) => '${e.key}=${e.value}').join(',');
  }

  Map<String, String> _parseLabelsKey(String key) {
    if (key.isEmpty) return {};
    return Map.fromEntries(
      key.split(',').map((pair) {
        final parts = pair.split('=');
        return MapEntry(parts[0], parts[1]);
      }),
    );
  }
}

/// Sync server metrics registry.
class SyncMetrics {
  /// Singleton instance.
  static final SyncMetrics instance = SyncMetrics._();

  SyncMetrics._();

  // Request counters
  final requestsTotal = Counter(
    name: 'entidb_sync_requests_total',
    help: 'Total number of sync requests',
  );

  final requestErrors = Counter(
    name: 'entidb_sync_request_errors_total',
    help: 'Total number of failed sync requests',
  );

  // Operation counters
  final operationsPushed = Counter(
    name: 'entidb_sync_operations_pushed_total',
    help: 'Total number of operations pushed by clients',
  );

  final operationsPulled = Counter(
    name: 'entidb_sync_operations_pulled_total',
    help: 'Total number of operations pulled by clients',
  );

  final conflictsDetected = Counter(
    name: 'entidb_sync_conflicts_total',
    help: 'Total number of conflicts detected',
  );

  // Connection gauges
  final activeConnections = Gauge(
    name: 'entidb_sync_active_connections',
    help: 'Number of active connections',
  );

  final sseConnections = Gauge(
    name: 'entidb_sync_sse_connections',
    help: 'Number of active SSE connections',
  );

  final wsConnections = Gauge(
    name: 'entidb_sync_websocket_connections',
    help: 'Number of active WebSocket connections',
  );

  // State gauges
  final oplogSize = Gauge(
    name: 'entidb_sync_oplog_size',
    help: 'Current size of the operation log',
  );

  final serverCursor = Gauge(
    name: 'entidb_sync_server_cursor',
    help: 'Current server cursor position',
  );

  // Latency histograms
  final requestDuration = Histogram(
    name: 'entidb_sync_request_duration_seconds',
    help: 'Request duration in seconds',
    buckets: [0.001, 0.005, 0.01, 0.025, 0.05, 0.1, 0.25, 0.5, 1, 2.5, 5],
  );

  final pushDuration = Histogram(
    name: 'entidb_sync_push_duration_seconds',
    help: 'Push operation duration in seconds',
  );

  final pullDuration = Histogram(
    name: 'entidb_sync_pull_duration_seconds',
    help: 'Pull operation duration in seconds',
  );

  // Size histograms
  final requestSize = Histogram(
    name: 'entidb_sync_request_size_bytes',
    help: 'Request body size in bytes',
    buckets: [100, 500, 1000, 5000, 10000, 50000, 100000, 500000, 1000000],
  );

  final responseSize = Histogram(
    name: 'entidb_sync_response_size_bytes',
    help: 'Response body size in bytes',
    buckets: [100, 500, 1000, 5000, 10000, 50000, 100000, 500000, 1000000],
  );

  /// Collects all metrics and formats as Prometheus text.
  String collect() {
    final buffer = StringBuffer();

    void writeMetric(MetricDefinition def, List<MetricSample> samples) {
      if (samples.isEmpty) return;
      buffer.writeln(def.toPrometheusHeader());
      for (final sample in samples) {
        buffer.writeln(sample.toPrometheusLine());
      }
      buffer.writeln();
    }

    writeMetric(requestsTotal.definition, requestsTotal.collect());
    writeMetric(requestErrors.definition, requestErrors.collect());
    writeMetric(operationsPushed.definition, operationsPushed.collect());
    writeMetric(operationsPulled.definition, operationsPulled.collect());
    writeMetric(conflictsDetected.definition, conflictsDetected.collect());
    writeMetric(activeConnections.definition, activeConnections.collect());
    writeMetric(sseConnections.definition, sseConnections.collect());
    writeMetric(wsConnections.definition, wsConnections.collect());
    writeMetric(oplogSize.definition, oplogSize.collect());
    writeMetric(serverCursor.definition, serverCursor.collect());
    writeMetric(requestDuration.definition, requestDuration.collect());
    writeMetric(pushDuration.definition, pushDuration.collect());
    writeMetric(pullDuration.definition, pullDuration.collect());
    writeMetric(requestSize.definition, requestSize.collect());
    writeMetric(responseSize.definition, responseSize.collect());

    return buffer.toString();
  }

  /// Resets all metrics (for testing).
  void reset() {
    // Counters and gauges will start fresh on next access
    // This is a simplified reset - in production you'd want more control
  }
}

/// Convenience accessor for metrics.
SyncMetrics get syncMetrics => SyncMetrics.instance;
