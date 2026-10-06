# Changelog

All notable changes are documented here. Format based on [Keep a Changelog](https://keepachangelog.com/).

## [Unreleased]
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
- Documentation website (Astro) with SEO guides.
