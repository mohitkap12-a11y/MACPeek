#!/usr/bin/env bash
# Creates dist/PortPeek-<version>.dmg and its SHA-256 from build/PortPeek.app.
set -euo pipefail
cd "$(dirname "$0")/.."
VERSION="${1:?usage: make-dmg.sh <version>}"
APP="build/PortPeek.app"
DMG="dist/PortPeek-${VERSION}.dmg"
STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT

mkdir -p dist
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
rm -f "$DMG"
hdiutil create -volname "PortPeek" -srcfolder "$STAGE" -ov -format UDZO "$DMG"
if [[ -n "${SIGN_IDENTITY:-}" ]]; then codesign --force --timestamp --sign "$SIGN_IDENTITY" "$DMG"; fi
(cd dist && shasum -a 256 "PortPeek-${VERSION}.dmg" > "PortPeek-${VERSION}.dmg.sha256")
echo "Created $DMG"; cat "dist/PortPeek-${VERSION}.dmg.sha256"
