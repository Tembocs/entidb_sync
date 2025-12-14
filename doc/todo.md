# Future Enhancements

## Completed ✅

1. **WebSocket transport** — Alternative to SSE for bidirectional real-time
   - Server: `WebSocketManager` with connection limits, keepalive pings, subscription broadcasting
   - Client: `WebSocketTransport` with auto-reconnect, exponential backoff, state streaming
   - Protocol: JSON-based messages (subscribe, operations, pull, push, ping/pong, ack, error)
   - Tests: Full coverage in both client and server packages

2. **Delta encoding** — For large entities, send only changed fields
   - `DeltaEncoder`: Computes field-level diffs between CBOR entities
   - `DeltaDecoder`: Applies patches to reconstruct updated entities
   - Operations: set, remove, increment, arrayAppend, arrayRemove, replace
   - `DeltaSizeEstimator`: Determines if delta is smaller than full replacement
   - Tests: Comprehensive coverage in protocol package

3. **Prometheus metrics** — Production observability integration
   - Metric types: `Counter`, `Gauge`, `Histogram` with label support
   - Pre-defined `SyncMetrics`: requests, errors, operations, connections, durations
   - `createMetricsMiddleware()`: Automatic request/response metric collection
   - `metricsHandler()`: `/metrics` endpoint with Prometheus text format
   - Tests: Full coverage including histogram bucket validation

4. **CI/CD Pipeline** — GitHub Actions workflow
   - Jobs: analyze, format, test (per-package), coverage, build, docker
   - Automated on push/PR to main branch
   - Artifact upload for server builds
   - Docker image publishing to GitHub Container Registry

## Remaining Ideas

- **Partial sync** — Sync only selected collections (beyond just filtering)
- **Conflict-free replicated data types (CRDTs)** — For certain data patterns
- **End-to-end encryption** — Client-side encryption before sync
- **Multi-region support** — Geo-distributed sync servers
- **Offline queue management UI** — Visualize pending operations