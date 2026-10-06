# Contributing

Thanks for helping! PortPeek stays deliberately small: **ports and processes only** — please open an
issue before proposing system-monitor-style features.

## Build
Requirements: macOS 13+, **full Xcode 15+** (Swift 5.9+). The Command Line Tools alone cannot build the app.
```bash
swift build            # build everything
swift test             # run unit + integration tests
swift run PortPeek     # run the menu-bar app from the terminal
scripts/build-app.sh   # produce build/PortPeek.app (ad-hoc signed unless SIGN_IDENTITY is set)
```
`PortPeekCore` is pure Foundation and also builds/tests on Linux (`swift test`).

## Troubleshooting the build
**`external macro implementation type 'SwiftUIMacros.StateMacro' could not be found … plugin for module 'SwiftUIMacros' not found`**
The active toolchain is `/Library/Developer/CommandLineTools`, which lacks SwiftUI's macro plugin. Install Xcode, open it once, then:
```bash
sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
rm -rf .build && swift build
```
`scripts/check-toolchain.sh` (run by `build-app.sh`) detects this and prints the same fix. The core library and its tests
(`swift test --filter PortPeekCoreTests`) do not need Xcode.

## Layout
- `Sources/PortPeekCore` — models, `PortDiscoveryProtocol`/`LsofPortDiscovery`, `PortParser`, `PortSearch`, `KillService`, `PermissionService`. No UI.
- `Sources/PortPeek` — AppKit/SwiftUI app (menu bar controller, store, views, settings).
- `Tests/PortPeekCoreTests` — fixtures in `Fixtures/` keep parser tests deterministic.
- `Website/` — Astro static site (`npm ci && npm run dev`); see [Website/TESTING.md](Website/TESTING.md).

## Rules
- Add tests with every change. Parser tests must use fixtures, never the live machine.
- No telemetry, no network calls, no third-party dependencies where native APIs suffice.
- Never weaken kill safety (revalidation, SIGTERM-first, explicit force).
- Never commit certificates, keys or passwords.
