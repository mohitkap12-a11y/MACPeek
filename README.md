# PortPeek

**See what's using your ports. Kill it in one click.**

PortPeek is a lightweight, open-source, native macOS menu-bar app for finding the process behind a
busy network port and freeing it — without opening Terminal.

> Screenshot/GIF: add `docs/screenshot.png` after the first build (see `Website/public/`).

## Features
- Searchable list of listening **TCP and UDP** ports, IPv4 and IPv6
- Search by port (partial too), process name, PID or address — instant and local
- Process detail view with permission hints (✓ can terminate · ⚠ permission required · 🔒 protected)
- **Safe kill**: re-scan → verify the PID still owns the port and is the same process (PID-reuse guard) →
  SIGTERM → verify exit and port release → optional, explicit force kill (SIGKILL)
- Polls (default every 2 s) only while the popover is open; zero background scanning when idle
- Light/dark mode, keyboard navigation, context menu (copy port/PID/address, open localhost)
- Settings: launch at login, refresh interval, confirm before kill, notifications, appearance
- No account, no telemetry, no network access, no third-party dependencies

## Install
Download `PortPeek-x.y.z.dmg` from [Releases](../../releases/latest), drag **PortPeek** to
**Applications**, launch it, and look for the icon in the menu bar. Releases are Developer ID signed
and notarized; verify the download against the published SHA-256 file.

## Build from source
Requires macOS 13+ and Xcode 15+ (Swift 5.9).
```bash
swift build
swift test
swift run PortPeek          # runs the menu-bar app
scripts/build-app.sh 0.1.0  # build/PortPeek.app (ad-hoc signed unless SIGN_IDENTITY is set)
scripts/make-dmg.sh 0.1.0   # dist/PortPeek-0.1.0.dmg + .sha256
```

## Architecture
```text
lsof ─▶ LsofPortDiscovery ─▶ PortParser ─▶ [PortInfo] ─▶ PortStore ─▶ SwiftUI
            (PortDiscoveryProtocol; a native libproc backend can replace it later)
KillService: validateTarget → signal → waitForExit → verifyPortReleased → (explicit) forceTerminate
```
- `Sources/PortPeekCore` — pure logic, platform independent, fully unit-tested with fixtures.
- `Sources/PortPeek` — AppKit/SwiftUI shell.
- `Website/` — Astro static marketing + docs + SEO guides.

## Security model
PortPeek runs as your user and never elevates privileges. It can only see/terminate what your user can.
Termination never trusts a stale PID. Details: [SECURITY.md](SECURITY.md).

## Privacy
PortPeek reads local process, socket and port information (via `lsof` and `sysctl`) and never
transmits it anywhere. No analytics, no telemetry, no accounts, no network entitlement.

## Contributing / License
See [CONTRIBUTING.md](CONTRIBUTING.md) and [CODE_OF_CONDUCT.md](CODE_OF_CONDUCT.md). Licensed under the [MIT License](LICENSE).
