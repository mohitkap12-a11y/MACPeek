#!/usr/bin/env bash
# PortPeek's SwiftUI code uses @State and friends, which are macros whose compiler plugin
# (SwiftUIMacros) ships only with full Xcode — not with the standalone Command Line Tools.
set -euo pipefail
dev_dir="$(xcode-select -p 2>/dev/null || true)"
if [[ "$dev_dir" == *CommandLineTools* ]]; then
  cat >&2 <<MSG
error: the active developer directory is the Command Line Tools ($dev_dir).
       Building the SwiftUI app needs full Xcode (it provides the SwiftUIMacros plugin).

  1. Install Xcode (15 or later) from the App Store or developer.apple.com
  2. Launch it once to accept the license, then run:
       sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
       sudo xcodebuild -license accept
  3. Re-run your build (delete .build first if you built before: rm -rf .build)

  Tip: 'swift test --filter PortPeekCoreTests' still works with the Command Line Tools, because
  the core library has no SwiftUI.
MSG
  exit 1
fi
