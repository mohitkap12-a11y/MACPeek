# Contributing

Thanks for helping! MacPeek stays deliberately small: **focused utilities for things macOS makes hard to
see.** Before proposing a new utility, use the *New utility request* issue template and the checklist in
[docs/architecture.md](docs/architecture.md#evaluating-a-new-utility).

## Build
Requirements: macOS 13+, **full Xcode 15+** (Swift 5.9+). The Command Line Tools alone cannot build the app.
```bash
swift build            # build everything
swift test             # run all unit + integration tests
swift run MacPeek      # run the menu-bar app from the terminal
open Package.swift     # open in Xcode
scripts/build-app.sh   # produce build/MacPeek.app (ad-hoc signed unless SIGN_IDENTITY is set)
```
The `*Kit` and `MacPeekCore` libraries are pure Foundation and also build/test on Linux (`swift test`).

## Troubleshooting the build
**`external macro implementation type 'SwiftUIMacros.StateMacro' could not be found … plugin for module 'SwiftUIMacros' not found`**
The active toolchain is `/Library/Developer/CommandLineTools`, which lacks SwiftUI's macro plugin. Install Xcode, open it once, then:
```bash
sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
rm -rf .build && swift build
```
`scripts/check-toolchain.sh` (run by `build-app.sh`) detects this and prints the same fix. The libraries and their
tests (`swift test --filter MacPeekCoreTests`) do not need Xcode.

## Layout
- `Sources/MacPeekCore` — shared, UI-free services every utility reuses: `ProcessTerminationService`,
  `PermissionService`, `ProcessInspecting`, `ShellCommand`, and the `UtilityCatalog`/`UtilitySelection` registry.
- `Sources/<Name>Kit` — one library per utility: models, parsers, services. No UI.
- `Sources/MacPeek` — the app: `App/` (menu bar), `Shell/` (launcher, router, manager, settings, about),
  `SharedUI/` (reusable native components), `Utilities/<Name>/` (each utility's module + views), `Support/`.
- `Tests/<Name>KitTests`, `Tests/MacPeekCoreTests` — fixtures in `Fixtures/` keep parser tests deterministic.
- `docs/` — architecture, development, release and per-utility documentation.

## Adding a utility
1. **Catalog entry.** Add (or flip from `.comingSoon` to `.available`) its `UtilityInfo` in
   `Sources/MacPeekCore/Registry/UtilityCatalog.swift`: name, the user question, tagline, summary, icon, and
   honest `reads`/`permissions` lists. Add it to `UtilityCatalog.all`.
2. **Kit.** Create `Sources/<Name>Kit` (+ `Tests/<Name>KitTests` with fixtures) with models, parsers and services.
   Wrap shell tools behind a protocol; never run commands from UI code; never build command lines from untrusted
   strings (`ShellCommand` passes arguments separately, never through a shell). Register both targets in `Package.swift`.
3. **Module.** Create `Sources/MacPeek/Utilities/<Name>/` with a `UtilityModule` (`launcherSummary()`,
   `didAppear()` to start refreshing, `didDisappear()` to **stop all expensive work**, `makeView()`) and its views,
   built from `SharedUI` components. Add a `Log` category `MacPeek.<Name>`.
4. **Register.** Add the module in `AppLifecycle`.
5. **Docs & tests.** Add `docs/utilities/<name>.md` (what it reads, refresh/sampling behavior, permissions, macOS
   version notes — separate verified OS facts from inference) and update README/CHANGELOG.
6. If it can terminate processes, use `ProcessTerminationService` with its own `TerminationResource`; never signal a PID directly.

## Rules
- Add tests with every change. Parser tests must use fixtures captured from a real Mac, never the live machine.
- No telemetry, no network calls except a check the user explicitly triggers (as NetPeek and DNSPeek do), no third-party dependencies where native APIs suffice.
- Never weaken kill safety (revalidation, SIGTERM-first, explicit force).
- Don't request permissions you don't need, and don't bypass macOS security controls.
- Never commit certificates, keys or passwords.
