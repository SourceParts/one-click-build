#!/bin/bash
set -e
cd "$(dirname "$0")"

swift build "$@"

BINARY="$(swift build --show-bin-path)/Build"
APP_DIR="Build.app/Contents/MacOS"

# Create .app bundle
mkdir -p "$APP_DIR"
cp "$BINARY" "$APP_DIR/Build"

# Sign the bundle (no entitlements -- ad-hoc signing for dev)
codesign --force --sign - Build.app 2>/dev/null

echo "Build complete: Build.app"
echo "Run: open Build.app"
