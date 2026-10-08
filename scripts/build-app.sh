#!/usr/bin/env bash
# Builds build/MacPeek.app from the SwiftPM executable. Usage: scripts/build-app.sh [version]
# Set SIGN_IDENTITY to a "Developer ID Application: ..." identity to sign with hardened runtime;
# otherwise the bundle is ad-hoc signed (fine for local use, NOT for distribution).
set -euo pipefail
cd "$(dirname "$0")/.."
scripts/check-toolchain.sh
VERSION="${1:-0.1.0}"
APP="build/MacPeek.app"

swift build -c release --arch arm64 --arch x86_64
BIN="$(swift build -c release --arch arm64 --arch x86_64 --show-bin-path)/MacPeek"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/MacPeek"
# App icon: drop a 1024x1024 PNG at Resources/AppIcon.png and it is converted to AppIcon.icns here.
if [[ -f Resources/AppIcon.png ]]; then
  ICON_TMP="$(mktemp -d)"; trap 'rm -rf "$ICON_TMP"' EXIT
  ICONSET="$ICON_TMP/AppIcon.iconset"; mkdir -p "$ICONSET"
  for s in 16 32 128 256 512; do
    sips -z $s $s Resources/AppIcon.png --out "$ICONSET/icon_${s}x${s}.png" >/dev/null
    sips -z $((s*2)) $((s*2)) Resources/AppIcon.png --out "$ICONSET/icon_${s}x${s}@2x.png" >/dev/null
  done
  iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"
elif [[ -n "${SIGN_IDENTITY:-}" ]]; then
  echo "error: Resources/AppIcon.png (1024x1024) is required for a signed/release build" >&2
  exit 1
else
  echo "warning: Resources/AppIcon.png missing — app will have the generic icon" >&2
fi
sed "s/__VERSION__/${VERSION}/g" Resources/Info.plist > "$APP/Contents/Info.plist"

if [[ -n "${SIGN_IDENTITY:-}" ]]; then
  codesign --force --timestamp --options runtime \
    --entitlements Resources/MacPeek.entitlements \
    --sign "$SIGN_IDENTITY" "$APP"
else
  echo "warning: SIGN_IDENTITY not set — ad-hoc signing (not distributable)" >&2
  codesign --force --sign - "$APP"
fi
codesign --verify --strict --verbose=2 "$APP"
echo "Built $APP ($VERSION)"
