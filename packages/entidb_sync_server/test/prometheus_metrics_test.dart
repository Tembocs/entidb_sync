/// Prometheus Metrics Tests
///
/// Tests for metrics collection and formatting.
import 'package:entidb_sync_server/entidb_sync_server.dart';
import 'package:test/test.dart';

void main() {
  group('Counter', () {
    test('starts at zero', () {
      final counter = Counter(name: 'test_counter', help: 'Test counter');
      expect(counter.get(), equals(0));
    });

    test('increments by 1 by default', () {
      final counter = Counter(name: 'test_counter', help: 'Test counter');
      counter.inc();
      expect(counter.get(), equals(1));
    });

    test('increments by custom value', () {
      final counter = Counter(name: 'test_counter', help: 'Test counter');
      counter.inc(value: 5);
      expect(counter.get(), equals(5));
    });

    test('tracks labels independently', () {
      final counter = Counter(name: 'test_counter', help: 'Test counter');
      counter.inc(labels: {'method': 'GET'});
      counter.inc(labels: {'method': 'POST'});
      counter.inc(labels: {'method': 'GET'});

      expect(counter.get(labels: {'method': 'GET'}), equals(2));
      expect(counter.get(labels: {'method': 'POST'}), equals(1));
    });

    test('collects all samples', () {
      final counter = Counter(name: 'test_counter', help: 'Test counter');
      counter.inc(labels: {'a': '1'});
      counter.inc(labels: {'a': '2'});

      final samples = counter.collect();
      expect(samples.length, equals(2));
    });

    test('formats prometheus line correctly', () {
      final counter = Counter(name: 'test_counter', help: 'Test counter');
      counter.inc(labels: {'method': 'GET', 'status': '200'}, value: 10);

      final samples = counter.collect();
      final line = samples.first.toPrometheusLine();

      expect(line, contains('test_counter'));
      expect(line, contains('method="GET"'));
      expect(line, contains('status="200"'));
      expect(line, contains('10'));
    });
  });

  group('Gauge', () {
    test('starts at zero', () {
      final gauge = Gauge(name: 'test_gauge', help: 'Test gauge');
      expect(gauge.get(), equals(0));
    });

    test('sets value', () {
      final gauge = Gauge(name: 'test_gauge', help: 'Test gauge');
      gauge.set(42);
      expect(gauge.get(), equals(42));
    });

    test('increments', () {
      final gauge = Gauge(name: 'test_gauge', help: 'Test gauge');
      gauge.set(10);
      gauge.inc(value: 5);
      expect(gauge.get(), equals(15));
    });

    test('decrements', () {
      final gauge = Gauge(name: 'test_gauge', help: 'Test gauge');
      gauge.set(10);
      gauge.dec(value: 3);
      expect(gauge.get(), equals(7));
    });

    test('tracks labels independently', () {
      final gauge = Gauge(name: 'test_gauge', help: 'Test gauge');
      gauge.set(100, labels: {'type': 'sse'});
      gauge.set(50, labels: {'type': 'ws'});

      expect(gauge.get(labels: {'type': 'sse'}), equals(100));
      expect(gauge.get(labels: {'type': 'ws'}), equals(50));
    });
  });

  group('Histogram', () {
    test('observes values', () {
      final histogram = Histogram(
        name: 'test_histogram',
        help: 'Test histogram',
        buckets: [0.1, 0.5, 1.0],
      );

      histogram.observe(0.05);
      histogram.observe(0.3);
      histogram.observe(0.8);
      histogram.observe(2.0);

      final samples = histogram.collect();
      expect(samples.length, greaterThan(0));
    });

    test('creates correct bucket samples', () {
      // Use unique name to avoid state from other tests
      final histogram = Histogram(
        name: 'test_request_duration_${DateTime.now().millisecondsSinceEpoch}',
        help: 'Request duration',
        buckets: [0.1, 0.5, 1.0],
      );

      histogram.observe(0.05); // bucket: 0.1, 0.5, 1.0, +Inf
      histogram.observe(0.3); // bucket: 0.5, 1.0, +Inf
      histogram.observe(0.8); // bucket: 1.0, +Inf
      histogram.observe(2.0); // bucket: +Inf only

      final samples = histogram.collect();

      // Find bucket samples - buckets are cumulative
      final bucket01 = samples.firstWhere(
        (s) => s.name.endsWith('_bucket') && s.labels['le'] == '0.1',
      );
      final bucket05 = samples.firstWhere(
        (s) => s.name.endsWith('_bucket') && s.labels['le'] == '0.5',
      );
      final bucket10 = samples.firstWhere(
        (s) => s.name.endsWith('_bucket') && s.labels['le'] == '1.0',
      );
      final bucketInf = samples.firstWhere(
        (s) => s.name.endsWith('_bucket') && s.labels['le'] == '+Inf',
      );

      // Cumulative bucket counts
      expect(bucket01.value, equals(1)); // 0.05 only
      expect(bucket05.value, equals(2)); // 0.05, 0.3
      expect(bucket10.value, equals(3)); // 0.05, 0.3, 0.8
      expect(bucketInf.value, equals(4)); // all
    });

    test('creates sum and count samples', () {
      final histogram = Histogram(
        name: 'test_histogram',
        help: 'Test histogram',
      );

      histogram.observe(1.0);
      histogram.observe(2.0);
      histogram.observe(3.0);

      final samples = histogram.collect();
      final sumSample = samples.firstWhere(
        (s) => s.name == 'test_histogram_sum',
      );
      final countSample = samples.firstWhere(
        (s) => s.name == 'test_histogram_count',
      );

      expect(sumSample.value, equals(6.0));
      expect(countSample.value, equals(3));
    });

    test('times function execution', () {
      final histogram = Histogram(
        name: 'test_histogram',
        help: 'Test histogram',
      );

      final result = histogram.time(() {
        // Simulate work
        var sum = 0;
        for (var i = 0; i < 1000; i++) {
          sum += i;
        }
        return sum;
      });

      expect(result, equals(499500));

      final samples = histogram.collect();
      final countSample = samples.firstWhere(
        (s) => s.name == 'test_histogram_count',
      );
      expect(countSample.value, equals(1));
    });

    test('tracks labels independently', () {
      final histogram = Histogram(
        name: 'test_histogram',
        help: 'Test histogram',
        buckets: [1.0],
      );

      histogram.observe(0.5, labels: {'endpoint': '/v1/pull'});
      histogram.observe(0.5, labels: {'endpoint': '/v1/push'});

      final samples = histogram.collect();
      final pullBucket = samples.where(
        (s) =>
            s.name == 'test_histogram_bucket' &&
            s.labels['endpoint'] == '/v1/pull',
      );
      final pushBucket = samples.where(
        (s) =>
            s.name == 'test_histogram_bucket' &&
            s.labels['endpoint'] == '/v1/push',
      );

      expect(pullBucket.length, greaterThan(0));
      expect(pushBucket.length, greaterThan(0));
    });
  });

  group('MetricSample', () {
    test('formats without labels', () {
      final sample = MetricSample(name: 'my_metric', value: 42);
      expect(sample.toPrometheusLine(), equals('my_metric 42.0'));
    });

    test('formats with labels', () {
      final sample = MetricSample(
        name: 'my_metric',
        value: 42,
        labels: {'foo': 'bar', 'baz': 'qux'},
      );
      final line = sample.toPrometheusLine();
      expect(line, contains('my_metric{'));
      expect(line, contains('foo="bar"'));
      expect(line, contains('baz="qux"'));
    });

    test('escapes label values', () {
      final sample = MetricSample(
        name: 'my_metric',
        value: 1,
        labels: {'path': '/v1/test\nvalue'},
      );
      final line = sample.toPrometheusLine();
      expect(line, contains('\\n'));
    });

    test('includes timestamp when provided', () {
      final sample = MetricSample(
        name: 'my_metric',
        value: 42,
        timestamp: DateTime.fromMillisecondsSinceEpoch(1000000),
      );
      final line = sample.toPrometheusLine();
      expect(line, contains('1000000'));
    });
  });

  group('MetricDefinition', () {
    test('formats header correctly', () {
      final def = MetricDefinition(
        name: 'http_requests_total',
        help: 'Total HTTP requests',
        type: MetricType.counter,
      );

      final header = def.toPrometheusHeader();
      expect(
        header,
        contains('# HELP http_requests_total Total HTTP requests'),
      );
      expect(header, contains('# TYPE http_requests_total counter'));
    });
  });

  group('SyncMetrics', () {
    test('singleton instance', () {
      expect(SyncMetrics.instance, same(syncMetrics));
    });

    test('tracks request totals', () {
      syncMetrics.requestsTotal.inc(
        labels: {'endpoint': '/v1/pull', 'method': 'POST', 'status': '200'},
      );

      final value = syncMetrics.requestsTotal.get(
        labels: {'endpoint': '/v1/pull', 'method': 'POST', 'status': '200'},
      );

      expect(value, greaterThan(0));
    });

    test('collects all metrics as prometheus text', () {
      // Add some metrics
      syncMetrics.activeConnections.set(5);
      syncMetrics.oplogSize.set(1000);

      final text = syncMetrics.collect();

      // Should have TYPE and HELP comments
      expect(text, contains('# HELP'));
      expect(text, contains('# TYPE'));
      expect(text, contains('entidb_sync'));
    });

    test('includes all metric types', () {
      final text = syncMetrics.collect();

      // Check for various metrics that have been used (have values)
      expect(text, contains('entidb_sync_requests_total'));
      expect(text, contains('entidb_sync_active_connections'));
      // Histograms only appear if they have observations
    });
  });

  group('Metrics with edge cases', () {
    test('handles empty labels', () {
      final counter = Counter(name: 'test', help: 'test');
      counter.inc();
      final samples = counter.collect();
      expect(samples.first.labels, isEmpty);
    });

    test('handles special characters in labels', () {
      final counter = Counter(name: 'test', help: 'test');
      counter.inc(labels: {'path': '/v1/sync?foo=bar&baz=123'});
      final samples = counter.collect();
      final line = samples.first.toPrometheusLine();
      expect(line, contains('path='));
    });

    test('handles zero values', () {
      final gauge = Gauge(name: 'test', help: 'test');
      gauge.set(0);
      expect(gauge.get(), equals(0));

      final samples = gauge.collect();
      expect(samples.first.value, equals(0));
    });

    test('handles negative values in gauge', () {
      final gauge = Gauge(name: 'test', help: 'test');
      gauge.set(-10);
      expect(gauge.get(), equals(-10));
    });
  });
}
