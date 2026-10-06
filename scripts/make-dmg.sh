#!/usr/bin/env bash
# Creates dist/MacPeek-<version>.dmg and its SHA-256 from build/MacPeek.app.
set -euo pipefail
cd "$(dirname "$0")/.."
VERSION="${1:?usage: make-dmg.sh <version>}"
APP="build/MacPeek.app"
DMG="dist/MacPeek-${VERSION}.dmg"
STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT

mkdir -p dist
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
rm -f "$DMG"
hdiutil create -volname "MacPeek" -srcfolder "$STAGE" -ov -format UDZO "$DMG"
if [[ -n "${SIGN_IDENTITY:-}" ]]; then codesign --force --timestamp --sign "$SIGN_IDENTITY" "$DMG"; fi
(cd dist && shasum -a 256 "MacPeek-${VERSION}.dmg" > SHA256SUMS)
echo "Created $DMG"; cat dist/SHA256SUMS
