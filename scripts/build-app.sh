#!/usr/bin/env bash
# Builds build/PortPeek.app from the SwiftPM executable. Usage: scripts/build-app.sh [version]
# Set SIGN_IDENTITY to a "Developer ID Application: ..." identity to sign with hardened runtime;
# otherwise the bundle is ad-hoc signed (fine for local use, NOT for distribution).
set -euo pipefail
cd "$(dirname "$0")/.."
VERSION="${1:-0.1.0}"
APP="build/PortPeek.app"

swift build -c release --arch arm64 --arch x86_64
BIN="$(swift build -c release --arch arm64 --arch x86_64 --show-bin-path)/PortPeek"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/PortPeek"
sed "s/__VERSION__/${VERSION}/g" Resources/Info.plist > "$APP/Contents/Info.plist"

if [[ -n "${SIGN_IDENTITY:-}" ]]; then
  codesign --force --timestamp --options runtime \
    --entitlements Resources/PortPeek.entitlements \
    --sign "$SIGN_IDENTITY" "$APP"
else
  echo "warning: SIGN_IDENTITY not set — ad-hoc signing (not distributable)" >&2
  codesign --force --sign - "$APP"
fi
codesign --verify --strict --verbose=2 "$APP"
echo "Built $APP ($VERSION)"
