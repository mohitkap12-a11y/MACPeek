# Changelog

All notable changes are documented here. Format based on [Keep a Changelog](https://keepachangelog.com/).

## [Unreleased]
### Added
- **SoundPeek**: audio input/output devices with the current defaults, connection type, sample rate, channels and the volume
  and mute state each device exposes (anything else reads "Not reported"). Updates when devices are plugged in or out while
  open. Set a default device or mute a device on request, with Undo. Never opens an audio stream, so no Microphone prompt.
- **StartupPeek**: read-only inventory of launch agents, launch daemons and MacPeek's own login item, each labelled with its
  source, scope and status, a "likely associated with" attribution and the signing team ID. States plainly that it cannot
  list System Settings' Login Items and never disables, removes or edits anything.
- **UpdatePeek**: macOS version and build, a button to Software Update, and, on request, the packages Homebrew reports as
  outdated (read-only, no `brew update`), with a copyable upgrade command. Does not check for macOS or other app updates and
  never claims anything is up to date.
- **PrivacyPeek**: informational guide to macOS privacy permissions with buttons to open each System Settings pane. Reads no
  per-app permission status and changes nothing.
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
