#!/usr/bin/env bash
# Writes the Homebrew cask for a release to stdout, from packaging/homebrew/macpeek.rb.in.
# Usage: scripts/render-homebrew-cask.sh <version> <sha256 of MacPeek-<version>.dmg>
set -euo pipefail
cd "$(dirname "$0")/.."
VERSION="${1:?version}"
SHA="${2:?sha256}"
[[ "$VERSION" =~ ^[0-9]+(\.[0-9]+)*$ ]] || { echo "not a stable version: $VERSION" >&2; exit 1; }
[[ "$SHA" =~ ^[0-9a-f]{64}$ ]] || { echo "not a SHA-256: $SHA" >&2; exit 1; }
sed -e "s/__VERSION__/${VERSION}/" -e "s/__SHA256__/${SHA}/" packaging/homebrew/macpeek.rb.in
