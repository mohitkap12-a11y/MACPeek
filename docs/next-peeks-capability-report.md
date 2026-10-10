# SoundPeek and UpdatePeek: capability report

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
| Set volume | **Shipped** as a slider where the volume property is settable (main volume, or channels 1 and 2). No permission needed. |
| Per-app volume/mute/routing | **Not shipped.** No public Core Audio API controls another app's audio without a virtual driver or audio-tap capture authorization. |
| "Which apps use audio" | **Not shipped.** No stable public API without capture permission was found. (Not verified on hardware; ships only if one is proven.) |
| Input level meter | **Omitted by design** (needs capture). |

### UpdatePeek
| Feature | Verdict |
|---|---|
| macOS version + build | **Shipped.** |
| macOS update availability | **Not shipped.** `softwareupdate --list` is unstable output, contacts Apple, and could not be validated on every supported macOS version here. UI says "not checked" and opens Software Update. |
| Homebrew outdated | **Shipped**, read-only, user-initiated, fixed argv, labelled as last-fetched index. Needs validation on a real Homebrew (see §6). |
| `brew upgrade` from MacPeek | **Not shipped.** Casks may prompt for a password and no-elevation behaviour is unverified. Copy-command instead. |
| npm outdated (global) | **Shipped**, read-only, user-initiated, fixed argv. **Contacts the npm registry**, so it is the one UpdatePeek check that makes a network request. Needs validation on a real Node install (see §6). |
| `npm install` from MacPeek | **Not shipped.** Global installs can need elevated rights; copy-command instead. |
| npm from nvm / fnm / Volta | **Not detected.** Only `/opt/homebrew/bin/npm` and `/usr/local/bin/npm`; stated in the UI. |
| Other apps | **"No supported update source"**, never inferred. |

## 3. Permission / entitlement diff
`git diff --stat -- Resources/ Package.swift` shows `Resources/MacPeek.entitlements` and `Resources/Info.plist`
**unchanged** (no additions, no usage-description strings, no helper, no login-item registration beyond the existing
`SMAppService.mainApp` in Settings). `Package.swift` only adds two internal Kit targets and their tests; no external
dependencies. Everything runs as the current user.

## 4. Implemented / partial / deferred
- **Implemented:** SoundPeek (inventory, live changes, default switch + Undo, volume slider, mute, report); UpdatePeek (OS
  version, Software Update link, Homebrew and global npm outdated, copy commands).
- **Partial:** UpdatePeek covers macOS version, Homebrew and global npm only.
- **Deferred:** per-app audio, audio-using-apps; macOS update check; in-app upgrades; global search integration.

## 5. Added dependencies
None. New SwiftPM targets: `SoundPeekKit`, `UpdatePeekKit` (+ test targets); new shared type `SystemSettingsPane` in
MacPeekCore. Framework used (system, no entitlement): CoreAudio.

## 6. What was and was not verified
- This work was written in a Linux sandbox **without a Swift toolchain**: it has **not been compiled or run** and no tests
  have been executed. CI (`swift build`, `swift test` on macOS 14 and Linux) is the first real build. Expect small compile
  fixes, particularly in the Core Audio wrappers and SwiftUI views.
- Not done: screenshots in light/dark mode, running on the oldest/latest macOS, real devices (USB/Bluetooth/HDMI), Homebrew,
  npm, the System Settings deep links. Record versions tested in the release notes.

### Manual release checklist
1. `swift build && swift test` on macOS 13 and the newest macOS; Linux CI green.
2. SoundPeek: built-in, USB, Bluetooth, HDMI; unplug/replug while open; sleep/wake; set default then Undo; drag the volume slider (and confirm the system volume follows, the slider holds your value while
   dragging, and a device without a writable volume shows no slider); mute; confirm no
   microphone indicator ever appears and no permission prompt is shown.
3. UpdatePeek: Homebrew and npm absent / present / outdated packages / broken; npm offline (expect a retryable failure, not an
   empty list); npm from nvm (expect "not found"); confirm nothing installs and no password prompt.
4. Diff `Resources/` against the previous release: must be empty. Screenshots light + dark.

## 7. Risks and decisions for the product owner
- Is "macOS update status: not checked" acceptable for v1, or should a validated `softwareupdate --list` provider be added later?
- The npm check is a network request to the user's configured registry, made only when Check is pressed. README, the website
  and the privacy text say so; confirm that wording is acceptable.
- Should nvm/fnm/Volta installs be detected? They put npm under the home folder in version-specific paths, which needs a
  decision on which Node version's globals to show.
