# SoundPeek, StartupPeek, UpdatePeek, PrivacyPeek: capability report

Scope: the handover "MacPeek Next Peeks". Hard constraint: **no new permissions, entitlements, helpers, drivers, elevation
or admin approval.**

## 1. Repository audit (before changes)
| Item | State |
|---|---|
| Deployment target | macOS 13 (`Package.swift` `.macOS(.v13)`, `LSMinimumSystemVersion` 13.0) |
| Sandbox / entitlements | **Not sandboxed**; `Resources/MacPeek.entitlements` is intentionally empty (hardened runtime only). No network entitlement. |
| `Info.plist` usage strings | None (`LSUIElement` menu-bar app) |
| Shell | `UtilityModule` protocol, `UtilityRegistry`, `UtilityRouter`, shared `SharedUI`, `UtilityCatalog` in MacPeekCore |
| Pattern | `<Name>Kit` (UI-free, Linux-buildable) + `Sources/MacPeek/Utilities/<Name>/{Module,Store,View}` |
| Tests / CI | XCTest per Kit; CI = `swift build` + `swift test` on macOS 14 and `swift test` on Linux (swift:5.9) |

The new Kits follow the same pattern, so Linux CI compiles them: Core Audio, Security and ServiceManagement code is behind
`#if canImport(...)`.

## 2. Feasibility, per feature (no extra permission)
### SoundPeek
| Feature | Verdict |
|---|---|
| Device list, defaults, transport, channels, rate, volume, mute | **Shipped.** Core Audio property reads need no permission; no stream is opened. |
| Live device changes | **Shipped**, listeners only while visible. |
| Set default input/output | **Shipped**, user-initiated, with Undo. Settable system property; no permission. |
| Mute | **Shipped** where the mute property is settable. |
| Set volume | **Deferred.** Feasible, but omitted to keep the first release's write surface to defaults and mute. |
| Per-app volume/mute/routing | **Not shipped.** No public Core Audio API controls another app's audio without a virtual driver or audio-tap capture authorization. |
| "Which apps use audio" | **Not shipped.** No stable public API without capture permission was found. (Not verified on hardware; ships only if one is proven.) |
| Input level meter | **Omitted by design** (needs capture). |

### StartupPeek
| Feature | Verdict |
|---|---|
| MacPeek's own login item | **Shipped** via `SMAppService.mainApp` (its documented purpose). |
| Other apps' Login Items / Background Items list | **Not possible.** No public enumeration API; `sfltool dumpbtm` needs admin; the BTM database is private. Stated in the UI. |
| Launch agents/daemons in the three conventional folders | **Shipped**, read-only FileManager + safe plist parsing. |
| Signing team attribution | **Shipped** via `SecStaticCode` (static, unvalidated, labelled). |
| Loaded/running state, `launchctl` override database | **Not read** (would need `launchctl`). |
| Any enable/disable/remove | **Out of scope by design.** |

### UpdatePeek
| Feature | Verdict |
|---|---|
| macOS version + build | **Shipped.** |
| macOS update availability | **Not shipped.** `softwareupdate --list` is unstable output, contacts Apple, and could not be validated on every supported macOS version here. UI says "not checked" and opens Software Update. |
| Homebrew outdated | **Shipped**, read-only, user-initiated, fixed argv, labelled as last-fetched index. Needs validation on a real Homebrew (see §6). |
| `brew upgrade` from MacPeek | **Not shipped.** Casks may prompt for a password and no-elevation behaviour is unverified. Copy-command instead. |
| Other apps | **"No supported update source"**, never inferred. |

### PrivacyPeek
Informational guide only: **Shipped.** No status, no TCC, no `tccutil`, no prompts.

## 3. Permission / entitlement diff
`git diff --stat -- Resources/ Package.swift` shows `Resources/MacPeek.entitlements` and `Resources/Info.plist`
**unchanged** (no additions, no usage-description strings, no helper, no login-item registration beyond the existing
`SMAppService.mainApp` in Settings). `Package.swift` only adds four internal Kit targets and their tests; no external
dependencies. Everything runs as the current user.

## 4. Implemented / partial / deferred
- **Implemented:** SoundPeek (inventory, live changes, default switch + Undo, mute, report); StartupPeek (read-only inventory,
  attribution, search, Finder/Settings navigation); UpdatePeek (OS version, Software Update link, Homebrew outdated, copy
  command); PrivacyPeek (guide + routes).
- **Partial:** StartupPeek inventory is intentionally incomplete (stated). UpdatePeek covers macOS version and Homebrew only.
- **Deferred:** SoundPeek volume setting, per-app audio, audio-using-apps; macOS update check; in-app upgrades;
  global search integration.

## 5. Added dependencies
None. New SwiftPM targets: `SoundPeekKit`, `StartupPeekKit`, `UpdatePeekKit`, `PrivacyPeekKit` (+ test targets); new
shared type `SystemSettingsPane` in MacPeekCore. Frameworks used (system, no entitlement): CoreAudio, Security, ServiceManagement.

## 6. What was and was not verified
- This work was written in a Linux sandbox **without a Swift toolchain**: it has **not been compiled or run** and no tests
  have been executed. CI (`swift build`, `swift test` on macOS 14 and Linux) is the first real build. Expect small compile
  fixes, particularly in the Core Audio / Security wrappers and SwiftUI views.
- Not done: screenshots in light/dark mode, running on the oldest/latest macOS, real devices (USB/Bluetooth/HDMI), Homebrew,
  every System Settings deep link. Record versions tested in the release notes.

### Manual release checklist
1. `swift build && swift test` on macOS 13 and the newest macOS; Linux CI green.
2. SoundPeek: built-in, USB, Bluetooth, HDMI; unplug/replug while open; sleep/wake; set default then Undo; mute; confirm no
   microphone indicator ever appears and no permission prompt is shown.
3. StartupPeek: compare with System Settings → Login Items; malformed plist fixture in a copy of a LaunchAgents folder;
   confirm no file changes (`ls -l` before/after).
4. UpdatePeek: Homebrew absent / present / outdated packages / broken; confirm nothing installs and no password prompt.
5. PrivacyPeek: every Open Settings button per macOS version; confirm fallbacks land on Privacy & Security.
6. Diff `Resources/` against the previous release: must be empty. Screenshots light + dark.

## 7. Risks and decisions for the product owner
- Is "macOS update status: not checked" acceptable for v1, or should a validated `softwareupdate --list` provider be added later?
- StartupPeek cannot list System Settings' Login Items; accept the stated limitation, or consider a guided "open and compare" flow?
- README/site wording on network use stays "only what you ask for": Homebrew is run with auto-update off, but Homebrew itself is third-party code.
- Privacy deep links and Local Network/Screen naming rely on observed behaviour that must be re-verified each macOS release.
