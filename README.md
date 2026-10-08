# MacPeek

**The tiny utilities macOS should have built in.**

MacPeek is a native, lightweight, open-source collection of focused macOS menu-bar utilities for finding,
inspecting and understanding the things macOS makes unnecessarily difficult to see. One small app, many
**Peeks** — switch on the ones you want, switch off the rest.

[![Sponsor](https://img.shields.io/badge/Sponsor-%E2%9D%A4-ea4aaa?logo=githubsponsors&logoColor=white)](https://github.com/sponsors/mohitkap12-a11y)

> Screenshot/GIF: add `docs/screenshot.png` after the first build.

## Utilities

| Utility | Answers | Status |
|---|---|---|
| **PortPeek** | What is using port 3000? Free it safely. | ✅ Available |
| **DisplayPeek** | What display configuration am I actually running? | ✅ Available |
| **USBPeek** | What is connected, and at what speed? | ✅ Available |
| **NetPeek** | Is my network connection actually healthy? | ✅ Available |
| **BatteryPeek** | What is my MacBook battery actually doing? | Coming soon |
| **SleepPeek** | Why isn't my Mac sleeping? | ✅ Available |
| **FileLockPeek** | What process is using this file? | ✅ Available |
| **ProcessPeek** | What exactly is this process? | ✅ Available |
| **DiskPeek** | Which app is using my disk right now? | ✅ Available |
| **EnvPeek** | What environment variables does this environment see? | ✅ Available |
| **DNSPeek** | Which DNS servers is my Mac using, and do they respond? | ✅ Available |

Open MacPeek's menu-bar icon to see the launcher. **Manage utilities** (or Settings → Manage utilities) lists
every utility with a description, what it reads, what access it needs, and an on/off switch. A utility that
is switched off does no work at all: no polling, no scanning, nothing in the launcher.

## Features
- Native Swift/SwiftUI, menu-bar only (no Dock icon), light/dark/system appearance
- One launcher, one search, one consistent compact UI for every utility
- **Safe process termination** shared by every utility that can kill something: re-check the target →
  verify the PID still owns the resource and is the same process (PID-reuse guard) → SIGTERM → verify
  exit and release → optional, explicit force kill (SIGKILL) after another re-check
- Utilities refresh only while their screen is open
- No account, no telemetry, no cloud, no third-party dependencies. The only network traffic is what you ask for (NetPeek pings, DNSPeek lookups)

## Install
Download `MacPeek-x.y.z.dmg` from [Releases](../../releases/latest), drag **MacPeek** to **Applications**,
launch it and look for the icon in the menu bar. Releases are Developer ID signed and notarized; verify the
download against the published `SHA256SUMS`.

## Build from source
Requires macOS 13+ and **full Xcode 15+** (Swift 5.9). The standalone *Command Line Tools* are not enough:
SwiftUI's `@State` macro needs the `SwiftUIMacros` plugin that only Xcode ships. If you see
`plugin for module 'SwiftUIMacros' not found`, run
`sudo xcode-select -s /Applications/Xcode.app/Contents/Developer`
(see [Troubleshooting the build](CONTRIBUTING.md#troubleshooting-the-build)).

```bash
swift build
swift test
swift run MacPeek            # runs the menu-bar app
open Package.swift           # or open it in Xcode
scripts/build-app.sh 0.1.0   # build/MacPeek.app (ad-hoc signed unless SIGN_IDENTITY is set)
scripts/make-dmg.sh 0.1.0    # dist/MacPeek-0.1.0.dmg + SHA256SUMS
```

## Architecture
```text
MacPeek (menu-bar app)                      Sources/MacPeek
 ├─ Shell: launcher · router · utility manager · settings · about
 ├─ SharedUI: PeekHeader · PeekRow · StatusBadge · EmptyState · CopyButton …
 └─ Utilities/<Name>/  view + module for each utility
MacPeekCore (shared, UI-free)               Sources/MacPeekCore
 └─ ProcessTerminationService · PermissionService · ProcessInspecting · ShellCommand · UtilityCatalog
<Name>Kit (one per utility, UI-free)        Sources/PortPeekKit, …
 └─ models · parsers · discovery · services — unit-tested with fixtures
```
The shell knows only utility metadata and navigation; each utility owns its models, services, views and tests.
Details: [docs/architecture.md](docs/architecture.md). Adding a utility: [CONTRIBUTING.md](CONTRIBUTING.md#adding-a-utility).

## Security model
MacPeek runs as your user and never elevates privileges. It can only see and terminate what your user can.
Termination never trusts a stale PID. Details: [SECURITY.md](SECURITY.md).

## Privacy
No account, no telemetry, no cloud. MacPeek reads local system information to show it to you and never
transmits it. The only network traffic is what you ask for: NetPeek's pings and DNSPeek's lookups, each run
only when you press the button. Each utility documents exactly what it reads (see Manage utilities).

## Roadmap
Ten utilities are built (PortPeek, FileLockPeek, DisplayPeek, USBPeek, SleepPeek, ProcessPeek, DiskPeek, EnvPeek, NetPeek,
DNSPeek); BatteryPeek is next (it needs a capture from a MacBook), then global search, accessibility and localization
polish → signed releases.

## Contributing / License
See [CONTRIBUTING.md](CONTRIBUTING.md) and [CODE_OF_CONDUCT.md](CODE_OF_CONDUCT.md). Licensed under the [MIT License](LICENSE).
