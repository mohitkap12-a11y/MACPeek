# Contributing

Thanks for helping! PortPeek stays deliberately small: **ports and processes only** — please open an
issue before proposing system-monitor-style features.

## Build
Requirements: macOS 13+, Xcode 15+ (Swift 5.9+).
```bash
swift build            # build everything
swift test             # run unit + integration tests
swift run PortPeek     # run the menu-bar app from the terminal
scripts/build-app.sh   # produce build/PortPeek.app (ad-hoc signed unless SIGN_IDENTITY is set)
```
`PortPeekCore` is pure Foundation and also builds/tests on Linux (`swift test`).

## Layout
- `Sources/PortPeekCore` — models, `PortDiscoveryProtocol`/`LsofPortDiscovery`, `PortParser`, `PortSearch`, `KillService`, `PermissionService`. No UI.
- `Sources/PortPeek` — AppKit/SwiftUI app (menu bar controller, store, views, settings).
- `Tests/PortPeekCoreTests` — fixtures in `Fixtures/` keep parser tests deterministic.
- `Website/` — Astro static site (`npm ci && npm run dev`).

## Rules
- Add tests with every change. Parser tests must use fixtures, never the live machine.
- No telemetry, no network calls, no third-party dependencies where native APIs suffice.
- Never weaken kill safety (revalidation, SIGTERM-first, explicit force).
- Never commit certificates, keys or passwords.
