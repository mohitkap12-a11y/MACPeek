#!/usr/bin/env bash
# Builds build/MacPeek.app from the SwiftPM executable. Usage: scripts/build-app.sh [version]
# Set SIGN_IDENTITY to a "Developer ID Application: ..." identity to sign with hardened runtime;
# otherwise the bundle is ad-hoc signed (fine for local use, NOT for distribution).
# SPARKLE_PUBLIC_ED_KEY is the EdDSA public key that update archives are verified against (required for signed builds;
# without it the app runs with in-app updates switched off).
set -euo pipefail
cd "$(dirname "$0")/.."
scripts/check-toolchain.sh
VERSION="${1:-0.1.0}"
APP="build/MacPeek.app"

swift build -c release --arch arm64 --arch x86_64
BIN_DIR="$(swift build -c release --arch arm64 --arch x86_64 --show-bin-path)"
BIN="$BIN_DIR/MacPeek"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$APP/Contents/Frameworks"
cp "$BIN" "$APP/Contents/MacOS/MacPeek"

# Sparkle (in-app updates) is a dynamic framework: bundle it and let the executable find it in Contents/Frameworks.
SPARKLE_FW="$(find "$BIN_DIR" .build/artifacts -type d -name Sparkle.framework -not -path '*ios*' -not -path '*maccatalyst*' 2>/dev/null | head -1 || true)"
if [[ -z "$SPARKLE_FW" ]]; then
  echo "error: Sparkle.framework not found after the build (looked in $BIN_DIR and .build/artifacts)" >&2
  exit 1
fi
ditto "$SPARKLE_FW" "$APP/Contents/Frameworks/Sparkle.framework"
# MacPeek is not sandboxed, so Sparkle's sandbox-only XPC helpers are not needed.
rm -rf "$APP/Contents/Frameworks/Sparkle.framework/Versions/B/XPCServices" "$APP/Contents/Frameworks/Sparkle.framework/XPCServices"
EXE="$APP/Contents/MacOS/MacPeek"
if ! otool -l "$EXE" | grep -q '@executable_path/../Frameworks'; then
  install_name_tool -add_rpath "@executable_path/../Frameworks" "$EXE"
fi
otool -l "$EXE" | grep -q '@executable_path/../Frameworks' || { echo "error: rpath to Contents/Frameworks is missing; the app would not find Sparkle" >&2; exit 1; }
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
if [[ -n "${SIGN_IDENTITY:-}" && -z "${SPARKLE_PUBLIC_ED_KEY:-}" ]]; then
  echo "error: SPARKLE_PUBLIC_ED_KEY is required for a signed/release build (see docs/release.md, Sparkle setup)" >&2
  exit 1
fi
sed -e "s/__VERSION__/${VERSION}/g" -e "s#__SPARKLE_PUBLIC_ED_KEY__#${SPARKLE_PUBLIC_ED_KEY:-__SPARKLE_PUBLIC_ED_KEY__}#" \
  Resources/Info.plist > "$APP/Contents/Info.plist"

FW="$APP/Contents/Frameworks/Sparkle.framework"
if [[ -n "${SIGN_IDENTITY:-}" ]]; then
  # Sign inside-out (helpers, then the framework, then the app) so notarization accepts every nested binary.
  # Locate the helpers wherever this Sparkle version keeps them, and refuse to continue if either is missing.
  AUTOUPDATE="$(find "$FW" -type f -name Autoupdate | head -1)"
  UPDATER_APP="$(find "$FW" -type d -name Updater.app | head -1)"
  [[ -n "$AUTOUPDATE" && -n "$UPDATER_APP" ]] || { echo "error: Sparkle's Autoupdate/Updater.app not found in $FW" >&2; exit 1; }
  codesign --force --timestamp --options runtime --sign "$SIGN_IDENTITY" "$AUTOUPDATE"
  codesign --force --timestamp --options runtime --sign "$SIGN_IDENTITY" "$UPDATER_APP"
  codesign --force --timestamp --options runtime --sign "$SIGN_IDENTITY" "$FW"
  codesign --force --timestamp --options runtime \
    --entitlements Resources/MacPeek.entitlements \
    --sign "$SIGN_IDENTITY" "$APP"
else
  echo "warning: SIGN_IDENTITY not set — ad-hoc signing (not distributable)" >&2
  codesign --force --sign - --deep "$APP"
fi
codesign --verify --strict --verbose=2 "$APP"
echo "Built $APP ($VERSION)"
