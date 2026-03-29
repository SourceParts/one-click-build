#!/bin/bash
set -e
cd "$(dirname "$0")"

swift build "$@"

BINARY="$(swift build --show-bin-path)/Build"
ENTITLEMENTS="Build.entitlements"

if [ -f "$ENTITLEMENTS" ]; then
    codesign --force --sign - --entitlements "$ENTITLEMENTS" "$BINARY" 2>/dev/null
else
    codesign --force --sign - "$BINARY" 2>/dev/null
fi

echo "Build complete: $BINARY"
