# Changelog

All notable changes are documented here. Format based on [Keep a Changelog](https://keepachangelog.com/).

## [Unreleased]
### Added
- Menu-bar app with searchable list of listening TCP/UDP ports (IPv4 + IPv6).
- Safe termination: re-scan, identity revalidation (PID-reuse guard), SIGTERM, exit + port-release
  verification, explicit force-kill step.
- Settings: launch at login, refresh interval, confirm-before-kill, notifications, appearance.
- Unit and integration tests with deterministic lsof fixtures.
- Packaging scripts and CI/release workflows (sign, notarize, DMG, checksum).
- Documentation website (Astro) with SEO guides.
