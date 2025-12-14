# EntiDB Sync Server Dockerfile
# 
# Build: docker build -t entidb-sync-server .
# Run: docker run -p 8080:8080 -e JWT_SECRET=your-secret entidb-sync-server

# Build stage
FROM dart:stable AS build

WORKDIR /app

# Copy pubspec files first for better layer caching
COPY packages/entidb_sync_protocol/pubspec.yaml packages/entidb_sync_protocol/
COPY packages/entidb_sync_server/pubspec.yaml packages/entidb_sync_server/

# Get dependencies for protocol package
WORKDIR /app/packages/entidb_sync_protocol
RUN dart pub get

# Get dependencies for server package
WORKDIR /app/packages/entidb_sync_server
RUN dart pub get

# Copy source code
WORKDIR /app
COPY packages/entidb_sync_protocol packages/entidb_sync_protocol
COPY packages/entidb_sync_server packages/entidb_sync_server

# Compile to native executable for optimal performance
WORKDIR /app/packages/entidb_sync_server
RUN dart compile exe bin/server.dart -o /app/server

# Runtime stage - minimal image
FROM debian:stable-slim

# Install required runtime libraries and ca-certificates for HTTPS
RUN apt-get update && apt-get install -y \
    ca-certificates \
    curl \
    && rm -rf /var/lib/apt/lists/*

# Create non-root user for security
RUN groupadd -r syncgroup && useradd -r -g syncgroup syncuser

WORKDIR /app

# Copy compiled binary from build stage
COPY --from=build /app/server /app/server

# Create data directory with correct permissions
RUN mkdir -p /app/data && chown -R syncuser:syncgroup /app

# Switch to non-root user
USER syncuser

# Environment defaults
ENV HOST=0.0.0.0
ENV PORT=8080
ENV DB_PATH=/app/data

# Expose the service port
EXPOSE 8080

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
    CMD curl -f http://localhost:8080/health || exit 1

# Run the server
ENTRYPOINT ["/app/server"]
