# Production Deployment Guide

This guide covers deploying EntiDB Sync Server to production environments.

## Table of Contents

1. [Quick Start](#quick-start)
2. [Docker Deployment](#docker-deployment)
3. [Environment Variables](#environment-variables)
4. [Security Checklist](#security-checklist)
5. [Scaling Considerations](#scaling-considerations)
6. [Monitoring](#monitoring)
7. [Troubleshooting](#troubleshooting)

---

## Quick Start

### Running the Server

```bash
# Install dependencies
cd packages/entidb_sync_server
dart pub get

# Set required environment variables
export JWT_SECRET="your-secure-256-bit-secret-key-here"
export DB_PATH="./sync_data"

# Run the server
dart run bin/server.dart
```

The server will start on `http://localhost:8080` by default.

---

## Docker Deployment

### Dockerfile

Create a `Dockerfile` in the repository root:

```dockerfile
# Build stage
FROM dart:stable AS build

WORKDIR /app

# Copy pubspec files first for better caching
COPY packages/entidb_sync_protocol/pubspec.yaml packages/entidb_sync_protocol/
COPY packages/entidb_sync_server/pubspec.yaml packages/entidb_sync_server/

# Get dependencies
WORKDIR /app/packages/entidb_sync_protocol
RUN dart pub get

WORKDIR /app/packages/entidb_sync_server
RUN dart pub get

# Copy source code
WORKDIR /app
COPY packages/entidb_sync_protocol packages/entidb_sync_protocol
COPY packages/entidb_sync_server packages/entidb_sync_server

# Compile to native executable
WORKDIR /app/packages/entidb_sync_server
RUN dart compile exe bin/server.dart -o /app/server

# Runtime stage
FROM debian:stable-slim

# Install required runtime libraries
RUN apt-get update && apt-get install -y \
    ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# Create non-root user
RUN useradd -r -u 1000 -g root syncuser
USER syncuser

WORKDIR /app

# Copy compiled binary
COPY --from=build /app/server /app/server

# Create data directory
RUN mkdir -p /app/data

# Set environment defaults
ENV HOST=0.0.0.0
ENV PORT=8080
ENV DB_PATH=/app/data

EXPOSE 8080

ENTRYPOINT ["/app/server"]
```

### Docker Compose

Create a `docker-compose.yml`:

```yaml
version: '3.8'

services:
  sync-server:
    build: .
    ports:
      - "8080:8080"
    environment:
      - HOST=0.0.0.0
      - PORT=8080
      - JWT_SECRET=${JWT_SECRET}
      - DB_PATH=/app/data
      - MAX_PULL_LIMIT=1000
      - MAX_PUSH_BATCH_SIZE=500
    volumes:
      - sync-data:/app/data
    restart: unless-stopped
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:8080/health"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 10s

volumes:
  sync-data:
```

### Building and Running

```bash
# Build the image
docker build -t entidb-sync-server .

# Run with Docker
docker run -d \
  -p 8080:8080 \
  -e JWT_SECRET="your-secure-secret" \
  -v sync-data:/app/data \
  --name sync-server \
  entidb-sync-server

# Or with Docker Compose
docker-compose up -d
```

---

## Environment Variables

| Variable | Required | Default | Description |
|----------|----------|---------|-------------|
| `HOST` | No | `localhost` | Bind address for the server |
| `PORT` | No | `8080` | Port number |
| `JWT_SECRET` | **Yes** | - | Secret key for JWT validation (min 32 chars) |
| `DB_PATH` | No | `./data` | Path to database storage |
| `MAX_PULL_LIMIT` | No | `1000` | Maximum operations per pull request |
| `MAX_PUSH_BATCH_SIZE` | No | `500` | Maximum operations per push request |
| `LOG_LEVEL` | No | `info` | Logging level (debug, info, warn, error) |
| `CORS_ORIGINS` | No | `*` | Allowed CORS origins (comma-separated) |
| `RATE_LIMIT_RPS` | No | `100` | Requests per second per client |
| `RATE_LIMIT_BURST` | No | `200` | Maximum burst size |
| `SSE_ENABLED` | No | `true` | Enable Server-Sent Events |
| `SSE_MAX_CONNECTIONS` | No | `1000` | Maximum SSE connections |

### Generating a Secure JWT Secret

```bash
# Using OpenSSL
openssl rand -base64 32

# Using Python
python3 -c "import secrets; print(secrets.token_urlsafe(32))"

# Using Dart
dart -e "import 'dart:math'; print(List.generate(32, (_) => Random.secure().nextInt(256).toRadixString(16).padLeft(2, '0')).join());"
```

---

## Security Checklist

### ✅ Before Going Live

- [ ] **Strong JWT Secret**: Use a cryptographically random secret (32+ chars)
- [ ] **HTTPS Only**: Deploy behind TLS termination (nginx, Cloudflare, etc.)
- [ ] **Rate Limiting**: Configure appropriate limits for your use case
- [ ] **CORS Policy**: Restrict origins to your domains only
- [ ] **Firewall**: Only expose port 8080 (or your configured port)
- [ ] **Non-Root User**: Run as non-privileged user (included in Dockerfile)
- [ ] **Read-Only Filesystem**: Mount app directory as read-only where possible
- [ ] **Secrets Management**: Use Docker secrets or cloud secrets manager
- [ ] **Network Isolation**: Run in private network/VPC
- [ ] **Log Sanitization**: Ensure sensitive data isn't logged

### JWT Token Security

```dart
// Token should contain:
// - sub: User/device ID
// - iat: Issued at timestamp
// - exp: Expiration (short-lived, e.g., 1 hour)
// - dbId: Authorized database ID

// Example token generation (server-side)
import 'package:entidb_sync_server/entidb_sync_server.dart';

final token = generateJwt(
  subject: 'device-123',
  claims: {'dbId': 'my-database'},
  secret: jwtSecret,
  expiresIn: Duration(hours: 1),
);
```

### HTTPS Configuration (nginx example)

```nginx
server {
    listen 443 ssl http2;
    server_name sync.example.com;

    ssl_certificate /etc/letsencrypt/live/sync.example.com/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/sync.example.com/privkey.pem;

    # Modern TLS configuration
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256;
    ssl_prefer_server_ciphers off;

    location / {
        proxy_pass http://localhost:8080;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_cache_bypass $http_upgrade;
    }

    # SSE requires special handling
    location /v1/events {
        proxy_pass http://localhost:8080;
        proxy_http_version 1.1;
        proxy_set_header Connection '';
        proxy_set_header Cache-Control 'no-cache';
        proxy_buffering off;
        proxy_read_timeout 24h;
        chunked_transfer_encoding off;
    }
}
```

---

## Scaling Considerations

### Horizontal Scaling

EntiDB Sync Server can be horizontally scaled with considerations:

1. **Sticky Sessions**: SSE connections require sticky sessions (use IP hash or session cookie)
2. **Shared Storage**: Database path must point to shared storage (NFS, EBS, etc.)
3. **Load Balancer**: Use nginx, HAProxy, or cloud load balancer

```nginx
# nginx upstream with sticky sessions
upstream sync_servers {
    ip_hash;  # Sticky sessions based on client IP
    server sync1:8080;
    server sync2:8080;
    server sync3:8080;
}
```

### Vertical Scaling

For single-server deployments:

| Users | Recommended Resources |
|-------|----------------------|
| < 100 | 1 CPU, 512MB RAM |
| 100-1000 | 2 CPU, 1GB RAM |
| 1000-10000 | 4 CPU, 4GB RAM |
| 10000+ | 8+ CPU, 8GB+ RAM |

### Connection Limits

```bash
# Increase system limits for high connection counts
echo "fs.file-max = 2097152" >> /etc/sysctl.conf
echo "net.core.somaxconn = 65535" >> /etc/sysctl.conf
sysctl -p

# Per-process limits in /etc/security/limits.conf
syncuser soft nofile 65535
syncuser hard nofile 65535
```

---

## Monitoring

### Health Check Endpoint

```bash
curl http://localhost:8080/health
# Returns: {"status": "ok"}
```

### Metrics Endpoint

```bash
curl http://localhost:8080/v1/stats
# Returns: {"cursor": 12345, "oplogSize": 1000, "sse": {"subscriptions": 50, "devices": 30}}
```

### Prometheus Metrics (example setup)

Add a custom metrics middleware:

```dart
// Future enhancement - Prometheus metrics
// GET /metrics -> prometheus format
```

### Logging

The server logs to stdout in JSON format (when `LOG_LEVEL` is configured):

```json
{"timestamp":"2024-01-15T10:30:00Z","level":"info","method":"POST","path":"/v1/push","status":200,"duration_ms":45}
```

### Alerting Recommendations

Set up alerts for:

- Health check failures (3+ consecutive)
- Response time > 1s (p95)
- Error rate > 1%
- SSE connection count near limit
- Disk usage > 80%
- Memory usage > 85%

---

## Troubleshooting

### Common Issues

#### 1. Connection Refused

```
Error: Connection refused on port 8080
```

**Solutions:**
- Check if server is running: `docker ps` or `ps aux | grep server`
- Verify HOST is set to `0.0.0.0` (not `localhost`) for Docker
- Check firewall rules

#### 2. JWT Authentication Failed

```
{"error": "Invalid token"}
```

**Solutions:**
- Verify JWT_SECRET matches between token generation and server
- Check token expiration (`exp` claim)
- Ensure token format is correct (Bearer <token>)

#### 3. SSE Connection Drops

```
Client SSE connection closed unexpectedly
```

**Solutions:**
- Check nginx/proxy buffering (must be disabled for SSE)
- Increase proxy_read_timeout
- Verify network stability

#### 4. High Memory Usage

**Solutions:**
- Reduce `MAX_PULL_LIMIT` and `MAX_PUSH_BATCH_SIZE`
- Limit SSE connections with `SSE_MAX_CONNECTIONS`
- Add memory limits in Docker: `--memory=2g`

#### 5. Slow Sync Performance

**Solutions:**
- Run benchmarks to identify bottleneck: `dart run benchmark/sync_benchmark.dart`
- Check disk I/O performance
- Consider SSD storage for DB_PATH
- Enable compression for large payloads

### Debug Mode

Enable debug logging:

```bash
LOG_LEVEL=debug dart run bin/server.dart
```

### Support

For issues and questions:
- GitHub Issues: https://github.com/your-org/entidb_sync/issues
- Documentation: See `/doc` directory
