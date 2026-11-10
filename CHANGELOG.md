# Changelog

All notable changes are documented here. Format based on [Keep a Changelog](https://keepachangelog.com/).

## [Unreleased]
### Added
- **Remote agent**: a new read, `disk.io`, returns how many bytes the drive behind each volume has read and written
  (from its block-storage driver's statistics in the I/O Registry). MacPeek Remote uses it to show an external
  drive's own read and write speed instead of the total for every disk.

### Fixed
- **USBPeek and the remote agent**: Bluetooth devices whose battery level system_profiler leaves out (macOS's Bluetooth
  menu still shows one) now get it from the I/O registry (`ioreg -k BatteryPercent`), by product name. Battery keys
  other than `device_batteryLevelMain`/`Left`/`Right`/`Case` are read too.

### Changed
- **Remote agent**: GPUPeek replies now carry Metal's facts about the GPU (family, memory the GPU may use), so the
  console can show GPU memory as a share of what the GPU may use.

## [0.3.2] - 2026-11-09
### Added
- **GPUPeek on the launcher**: a GPU ring tile between CPU and Memory (GPU busy, with GPU memory in use). With four
  rings the launcher shows compact tiles in one row. The GPUPeek screen now follows CPUPeek's layout: rings for GPU
  memory, GPU busy and the Neural Engine, a chart since opened, details including Metal's GPU family and the memory the
  GPU may use, power bars and the processes using the GPU.
- **ContainerPeek**: answers "Which containers and VMs are running, and what are they costing me?" Docker and Podman
  containers (with the Docker context: Docker Desktop, OrbStack, Colima, Rancher Desktop) with published ports, Compose
  project, CPU and memory; Start, Stop, Restart, Pause, Resume and Remove after re-checking the container (Remove never
  deletes volumes or images); the last 200 log lines on request; Lima, Colima, Tart and Parallels VMs; and the hypervisor
  processes on the Mac with their CPU and memory. See [docs/utilities/containerpeek.md](docs/utilities/containerpeek.md).
- **GPUPeek**: GPU load, renderer/tiler use and GPU memory as the driver reports them, processes using the GPU with their
  share of GPU time, and on Apple silicon the CPU, GPU and Neural Engine power from macOS's energy counters (IOReport,
  loaded only if present). macOS reports no Neural Engine utilization without administrator rights, so its power is shown
  and labelled as such. See [docs/utilities/gpupeek.md](docs/utilities/gpupeek.md).
- **ModelPeek**: Ollama, LM Studio, MLX, llama.cpp and llamafile runners, the models they have loaded (from Ollama's and
  LM Studio's APIs on 127.0.0.1, or the runner's model argument), and the memory, CPU and GPU each runner uses. Command
  lines are never kept beyond the model argument. See [docs/utilities/modelpeek.md](docs/utilities/modelpeek.md).
- **NetPeek**: system proxy settings, VPN services and their status, Tailscale state (exit node, peers, health) and
  remembered Wi-Fi networks, with plain-language notes on how each can change what works.
- **DNSPeek**: `/etc/hosts` entries and `/etc/resolver/*` files, and a note next to a lookup when one of them applies to
  the name.
- **USBPeek**: Bluetooth devices with their battery levels (left, right and case for AirPods), low batteries highlighted.
- **ProcessPeek**: the full parent chain, the launchd job or app that started a process (and whether launchd keeps it
  alive), its open files on request, and a "Safe to end?" assessment with reasons.
- **Remote management**: `network.extras`, `dns.overrides`, `bluetooth.devices`, `processes.origin`,
  `processes.openFiles`, `containers.snapshot`, `gpu.snapshot`, `models.snapshot` and the `containers.action` action
  (gated like the other actions). See [docs/remote.md](docs/remote.md).
- **Remote management: accounts (protocol version 2).** A MacPeek Remote console signed in to an account can pair this
  Mac into the account, so every device of that account can connect, with the access chosen at the Mac (the code and
  four words are unchanged, and the Mac says the pairing adds it to an account). Consoles paired before keep working and
  can offer "Move this Mac to your account", which the Mac announces and lets you undo. Devices removed from the
  account are refused as soon as one of its consoles hands the Mac the account's signed revocation list. Settings shows
  the account, its devices, **Undo move** and **Remove from account**. MacPeek itself still needs no account.
- **Remote management**: `dns.configuration` (the resolvers macOS is using) and `dns.probe` (ask one DNS server for a
  name) for MacPeek Remote's DNSPeek view. The Mac only asks servers in its own configuration, and only for a valid host
  name, so a console cannot use it to send queries anywhere else.
- Shared `LooseJSON`, `ExecutableLocator` and `ByteSizeText` (MacPeekCore) for reading other tools' JSON and sizes.
### Changed
- `docs/remote.md` documents protocol version 2: workspace keys and certificate chains, signed revocation lists, the
  Mac's claim and the workspace roles (`owner`, `admin`, `operator`, `viewer`).
- CI and the release workflow run on macOS 15 runners (GitHub retired the macOS 14 image on November 2, 2026).
- `Package.resolved` is no longer tracked.
### Fixed
- **Remote management: pairing and connections hardened.** Every connection now shares one attempt limit against the
  code on screen, so connections opened before a code was withdrawn can no longer keep guessing. A cancelled pairing is
  never confirmed, a pairing finishes exactly once when the console's confirmation and the decision on the Mac arrive
  together, a connection closed while a request ran (revoked, turned off) is not reopened and gets no answer, and
  switching Remote management off right after on no longer leaves a listener running.
### Upgrading
- No new permissions or entitlements. Remote management stays off unless you turn it on, and consoles paired with 0.3.0
  or 0.3.1 keep working.

## [0.3.1] - 2026-10-27
Built from the same commit as 0.3.0; no code changes.

## [0.3.0] - 2026-10-27
### Added
- **MemoryPeek**: answers "Is my Mac actually running out of memory?" It leads with memory pressure (Normal, Warning,
  Critical) and a plain-language reading, then shows how memory is split (app memory, wired, compressed, cached files, free),
  how much has been moved to disk (swap), and the 15 processes with the largest memory footprint (the figure Activity Monitor
  shows). Reads only while its screen is open; the launcher shows the current pressure. It never "frees" memory.
- **CPUPeek**: answers "What is making my Mac slow or hot right now?" Overall and per-core CPU use, the chip and its
  performance/efficiency cores, load average, macOS's thermal state, and the 20 busiest processes over the last interval
  (100 % = one core, as in Activity Monitor). Sampled only while its screen is open, and labelled as sampled; the launcher
  shows the load average, or "Running hot".
- **DiskPeek: Storage.** DiskPeek now also shows each local drive's capacity and available space, including how much of it is
  space macOS frees by itself, with a "Low space" badge under 10 %. Network drives are skipped. It never scans your folders.
- Shared `SystemProcessUsageReader`, `ProcessCounterSampler`, `CancellationFlag` and `ByteCountText` (MacPeekCore): one
  libproc scan (CPU time, memory footprint, disk I/O, with process names cached), one set of sampling rules and one byte
  formatter for DiskPeek, MemoryPeek, CPUPeek and ProcessPeek. No new permissions or entitlements.
- The data models in MacPeekCore and every `<Name>Kit` (snapshots, rows, reports and their enums, plus process-termination
  targets and results) are now `Codable`, so they can be saved or sent as JSON. Readers, services, parsers and formatters
  are unchanged, and nothing is encoded or sent anywhere by MacPeek itself.
- `DeviceInfo` and `SystemDeviceInfoReader` (MacPeekCore): computer name, Bonjour name, model identifier, macOS version
  and boot time (uptime), with `UptimeText` for labels like "6d 4h". Read-only, no permission.
- Network throughput (NetPeekKit): `SystemInterfaceCountersReader` reads per-interface byte counters with `getifaddrs` and
  `TrafficSampler` turns consecutive readings into download and upload rates. Totals leave out loopback, VPN tunnels and
  Apple's peer-to-peer interfaces, and a 32-bit counter wrap is handled. Not yet shown in the app.
- `MemoryStats.swapTotalBytes`: the swap space macOS has set aside, next to the amount used.
- **Remote management** (Settings → Remote management), **off by default**, for the upcoming MacPeek Remote console.
  When turned on, MacPeek listens on the local network and advertises itself over Bonjour; while off, nothing listens or
  connects. Consoles must be paired on the Mac with a one-time code and four words compared on both screens, every
  connection is end-to-end encrypted and checked against the paired key, actions need a separate **Allow actions**
  switch and a "View and act" pairing, and every action and pairing change is recorded in an activity log. A dot on the
  menu-bar icon shows while it is on. New UI-free targets `RemoteCrypto`, `RemoteProtocol` and `RemoteAgent`, tested on
  Linux; the protocol is documented in `docs/remote.md`. The app asks for local network access the first time it is
  turned on (`NSLocalNetworkUsageDescription`).
- Dependabot for SwiftPM and GitHub Actions.
### Changed
- **New launcher and look.** CPU, Memory and Disk rings across the top (CPU in use and load, memory in use, startup disk
  used and free), then every other enabled utility as a row with its summary (and the search field). New dark and light colours, a sun/moon
  button in the launcher to switch between them, and a taller popover (380 x 640). The rings update live at the refresh
  interval while the launcher is on screen (CPU from consecutive readings) and stop when you open a utility or close the
  menu; the last readings stay on screen until new ones arrive.
- CPUPeek, MemoryPeek and DiskPeek follow the refresh interval in Settings, down to 1 second, and show values almost at
  once: the second sample follows the first after 0.4 s instead of a full interval.
- **CPUPeek, MemoryPeek and DiskPeek redesigned**: rings and gauges, a "since opened" history chart, per-core bars, a
  memory pressure gauge and colour bar, and a startup-disk card with live read/write rates and capacity.
- DiskPeek and ProcessPeek format sizes with the shared formatter (one decimal below 100, e.g. ProcessPeek now shows "23.4 MB"
  where it showed "23 MB").
- CI actions updated: `actions/checkout` 4 to 7, `softprops/action-gh-release` 2 to 3.
### Fixed
- DiskPeek no longer reports a long-running process that could not be read in the previous sample as if its whole lifetime
  of disk I/O happened in one interval; it starts a new baseline instead.

## [0.2.2] - 2026-10-17
### Added
- **Support MacPeek.** A new Support screen (heart button in the launcher footer, and a link in About) with the GitHub Sponsors
  and PayPal links from the website. Optional; links only open in your browser when you click them.
### Changed
- Softer popover background in light mode.
- Release docs and workflow messages: the website deploy hook is now a Cloudflare Workers Builds hook.

## [0.2.1] - 2026-10-13
### Fixed
- **ProcessPeek now updates live.** The process list, search results and the opened process (including its listening ports)
  were read only when the screen opened or on manual refresh, so they went stale. They now refresh every
  **Settings → Refresh every** seconds while ProcessPeek is on screen, without a loading flash, and stop when you leave it.

## [0.2.0] - 2026-10-13
### Added
- **In-app updates.** MacPeek can now update itself (using [Sparkle](https://sparkle-project.org)). About once a day it asks
  GitHub whether a newer release exists, and **Settings → Updates → Check for Updates…** checks on demand. Automatic
  checks are on by default and can be switched off in Settings. Updates are verified with an EdDSA signature and Apple's
  code signature before they are installed; nothing about you or your Mac is sent beyond an ordinary web request.
  Sparkle is MacPeek's only third-party dependency. Builds without an update key (`swift run`, local builds) run with
  updates switched off.
- The release workflow signs each DMG with the update key and publishes an `appcast.xml` feed next to the DMG.
### Changed
- README, SECURITY, About and Settings now describe the daily update check alongside the checks you start yourself.
- `docs/release.md` is now a full release runbook: one-time signing and notarization setup, Sparkle keys, every-release
  steps and troubleshooting.
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
