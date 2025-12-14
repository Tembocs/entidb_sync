#!/bin/bash

# EntiDB Sync - Development Setup Script
# Checks prerequisites and installs dependencies for all packages

set -e

echo "EntiDB Sync - Development Setup"
echo "================================"
echo ""

# Check Dart SDK version
echo "Checking Dart SDK version..."
if ! command -v dart &> /dev/null; then
    echo "❌ Dart SDK not found. Please install from https://dart.dev/get-dart"
    exit 1
fi

DART_VERSION=$(dart --version 2>&1 | grep -oP 'Dart SDK version: \K[0-9.]+' || echo "unknown")
echo "✓ Found Dart SDK $DART_VERSION"

# Check if version is >= 3.10.1
if [ "$DART_VERSION" != "unknown" ]; then
    MAJOR=$(echo $DART_VERSION | cut -d. -f1)
    MINOR=$(echo $DART_VERSION | cut -d. -f2)
    PATCH=$(echo $DART_VERSION | cut -d. -f3)
    
    if [ "$MAJOR" -lt 3 ] || ([ "$MAJOR" -eq 3 ] && [ "$MINOR" -lt 10 ]) || ([ "$MAJOR" -eq 3 ] && [ "$MINOR" -eq 10 ] && [ "$PATCH" -lt 1 ]); then
        echo "⚠️  Warning: Dart SDK 3.10.1+ is required (you have $DART_VERSION)"
        echo "   Upgrade with: dart channel stable && dart upgrade"
        exit 1
    fi
fi

echo ""
echo "Installing dependencies..."
echo ""

# Install protocol package
echo "📦 entidb_sync_protocol"
cd packages/entidb_sync_protocol
dart pub get
cd ../..

# Install client package
echo "📦 entidb_sync_client"
cd packages/entidb_sync_client
dart pub get
cd ../..

# Install server package
echo "📦 entidb_sync_server"
cd packages/entidb_sync_server
dart pub get
cd ../..

echo ""
echo "✅ Setup complete!"
echo ""
echo "Next steps:"
echo "  • Review documentation: doc/architecture.md"
echo "  • Run tests: dart test packages/<package>/test"
echo "  • Start development: see CONTRIBUTING.md"
