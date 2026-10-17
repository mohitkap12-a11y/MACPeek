# Changelog

All notable changes are documented here. Format based on [Keep a Changelog](https://keepachangelog.com/).

## [0.2.0] - Unreleased
### Added
- **In-app updates.** MacPeek can now update itself (using [Sparkle](https://sparkle-project.org)). About once a day it asks
  GitHub whether a newer release exists, and **Settings → Updates → Check for Updates…** checks on demand. Automatic
  checks are on by default and can be switched off in Settings. Updates are verified with an EdDSA signature and Apple's
  code signature before they are installed; nothing about you or your Mac is sent beyond an ordinary web request.
  Sparkle is MacPeek's only third-party dependency. Builds without an update key (`swift run`, local builds) run with
  updates switched off.
- **Support MacPeek.** A new Support screen (heart button in the launcher footer, and a link in About) with the GitHub Sponsors
  and PayPal links from the website. Optional; links only open in your browser when you click them.
- The release workflow signs each DMG with the update key and publishes an `appcast.xml` feed next to the DMG.
### Changed
- README, SECURITY, About and Settings now describe the daily update check alongside the checks you start yourself.
- `docs/release.md` is now a full release runbook: one-time signing and notarization setup, Sparkle keys, every-release
  steps and troubleshooting.
### Fixed
- **ProcessPeek now updates live.** The process list, search results and the opened process (including its listening ports)
  were read only when the screen opened or on manual refresh, so they went stale. They now refresh every
  **Settings → Refresh every** seconds while ProcessPeek is on screen, without a loading flash, and stop when you leave it.
### Upgrading
- 0.1.0 has no updater, so install 0.2.0 by downloading it once; from then on MacPeek can offer later releases itself.

## [0.1.0] - 2026-10-13
First public release: a signed, notarized menu-bar app with PortPeek, FileLockPeek, ProcessPeek, DiskPeek, EnvPeek, NetPeek,
DNSPeek, DisplayPeek, USBPeek, SleepPeek, SoundPeek and UpdatePeek. The detailed entries below were collected before release.

### Added
- **SoundPeek**: audio input/output devices with the current defaults, connection type, sample rate, channels and the volume
  and mute state each device exposes (anything else reads "Not reported"). Updates when devices are plugged in or out while
  open. Set a default device; on the default output device, move a volume slider and mute it where the device allows it. Shows a message only when a change fails. Never
  opens an audio stream, so no Microphone prompt.
- **UpdatePeek**: macOS version and build; the macOS updates macOS itself lists (read from its own Software Update record, shown
  on the launcher too) or, when you press Check now, that `softwareupdate --list` reports (asks Apple's update servers); a
  prominent button to open Software Update; and, on request, the packages Homebrew reports as outdated (read-only, no
  `brew update`) and the global npm packages `npm outdated -g` reports (asks the npm registry). Each Homebrew and npm package has
  a copyable upgrade command, and npm packages have an **Update** button that asks you to confirm and then runs
  `npm install -g <name>@latest` (never elevated, never cancelled halfway; when npm lacks permission, the row offers the same command with `sudo` to copy into Terminal). Never installs macOS or Homebrew updates.
- Shared `SystemSettingsPane` (MacPeekCore): System Settings deep links with ordered fallbacks.
- **NetPeek**: active interface, IPv4/IPv6 addresses, router and DNS servers, Wi-Fi signal/noise/channel/standard/link rate
  (macOS hides the network name without Location access, and NetPeek says so), and, only when you press Run checks, pings
  to your router and DNS servers. Measured facts are labelled apart from inference.
- **DNSPeek**: the DNS servers macOS uses (from `scutil --dns`), search domains, per-domain, multicast and scoped resolvers,
  and, only when you press Run lookup, a lookup through macOS plus a direct query to each server. Read-only.
- **ProcessPeek: Kill Process** with the same safe flow as PortPeek and FileLockPeek: confirm, re-check name and kernel start
  time (a reused PID is never signalled), SIGTERM, verify exit, then an explicit Force Kill. Ending `loginwindow` or the user
  `launchd` always asks first. Protected processes cannot be killed.
- **ProcessPeek**: a searchable process list; open a process for its path, parent, user, start time, CPU and memory,
  command line, listening ports and children (jump between them). Read-only; the command line is read only on request.
- **DiskPeek**: per-process disk read/write rates and totals, sampled with `proc_pid_rusage` only while its screen is
  open and always labelled as sampled. Other users' processes are counted but not shown.
- **EnvPeek**: search environment variables, inspect PATH entry by entry, copy `NAME=value`. Sources are always
  labelled (MacPeek's own environment, or one process by PID via `sysctl KERN_PROCARGS2`). Credential-looking values
  are hidden until revealed; nothing is logged or stored.
- **DisplayPeek**: each connected display's panel resolution, "looks like" resolution, refresh rate, scaling and the
  other details macOS reports, with one-click copy (serial numbers excluded). Reads only while its screen is open.
- **USBPeek**: connected USB devices as a tree by bus (vendor, vendor:product ID, negotiated link speed, declared USB
  version, class) plus Thunderbolt / USB4 port status. Read from `ioreg` because `system_profiler SPUSBDataType` returned
  nothing on a Mac with devices attached. Serial numbers are never read.
- **SleepPeek**: what is keeping the Mac awake (assertions and the processes behind them), macOS's own "prevented by"
  summary, and, on request, recent sleep/wake events. Read-only; every statement is labelled verified or inference.
- `scripts/capture-fixtures.sh`: no longer hangs on the streaming `pmset -g assertionslog`; every capture has a time limit.
- **FileLockPeek**: choose (or drop, or paste) a file or folder and see which of your processes have it open, locked,
  as their working directory, as their executable or memory-mapped; copy PID/path, reveal in Finder, and optionally end a
  holder through the shared safe-termination service. Scans only on request; folder scans are recursive.
### Changed
- Shared `Banner`, `KillConfirmationView` and `LsofEscape` moved out of PortPeek so utilities reuse them.

### Changed
- **Rebrand: PortPeek is now a utility inside MacPeek** — a menu-bar app hosting a family of small utilities.
  Bundle ID `app.macpeek.MacPeek`, `MacPeek-x.y.z.dmg`, `SHA256SUMS`.
- Shared `ProcessTerminationService` (MacPeekCore) replaces PortPeek-specific kill logic; PortPeek uses it through a
  `TerminationResource`. Behavior and safety guarantees unchanged.
### Added
- MacPeek shell: launcher with search, utility router, **Manage utilities** screen (description, what each utility reads,
  permissions, on/off switch; disabled utilities do no work), settings, about, shared native UI components.
- `UtilityCatalog` listing all planned utilities (Display, USB, Net, Battery, Sleep, FileLock, Process, Disk, Env, DNS
  shown as "Coming soon").
- `scripts/capture-fixtures.sh` to capture real, masked macOS command output for parser fixtures.
- Docs: architecture, development, release, per-utility pages; new-utility issue template.

### Added (earlier, PortPeek)
- Menu-bar app with searchable list of listening TCP/UDP ports (IPv4 + IPv6).
- Safe termination: re-scan, identity revalidation (PID-reuse guard), SIGTERM, exit + port-release
  verification, explicit force-kill step.
- Settings: launch at login, refresh interval, confirm-before-kill, notifications, appearance.
- Unit and integration tests with deterministic lsof fixtures.
- Packaging scripts and CI/release workflows (sign, notarize, DMG, checksum).
