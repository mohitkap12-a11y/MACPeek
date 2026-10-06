---
layout: ../../layouts/Article.astro
title: "MacPeek Troubleshooting | MacPeek Docs"
description: "Fixes for common MacPeek problems: a utility is missing, a port is missing, Kill does nothing, Launch at login fails, or macOS blocks the app."
h1: "Troubleshooting"
section: docs
date: "2026-10-06"
---
## A utility is missing from the launcher
Open **Settings → Manage utilities** (or the **Manage utilities** link in the launcher footer) and check its switch. Utilities marked *Coming soon* are not released yet and cannot be switched on.

## A port I expect is missing
- It may belong to another user or root. Check with `sudo lsof -nP -iTCP -sTCP:LISTEN`.
- Only *listening* sockets are shown, not outgoing connections.
- Press ⟳ to refresh; the list updates every 2 seconds while open.

## Kill says "Permission denied"
The process isn't yours. See [permissions](/docs/permissions/).

## Kill says "did not exit"
The process ignored SIGTERM (it may be hung or cleaning up). Wait a moment and refresh, or use **Force Kill**, which ends it immediately without cleanup.

## "Target changed" or "Port already released"
That's PortPeek protecting you: the port changed owner between scan and kill, so nothing was killed. Refresh and retry.

## Port 5000 or 7000 is used by "ControlCenter"
That's macOS **AirPlay Receiver**. Turn it off in System Settings → General → AirDrop & Handoff → AirPlay Receiver.

## Paste does not work in a text field
Update to the latest MacPeek. Earlier builds had no Edit menu, so `⌘V`, `⌘C`, `⌘A` and `⌘Z` did not reach text fields. They work in every field now.

## The Light theme does not apply
Choose it in **Settings → Appearance**; it applies to the popover straight away. If it does not, [open an issue](https://github.com/mohitkap12-a11y/MACPeek/issues) with your macOS version.

## USBPeek does not show a device I just plugged in
USBPeek updates every few seconds while its screen is open. Press `⌘R` to read immediately. Serial numbers are never shown, so two identical devices differ only by where they are connected.

## DiskPeek shows no rates yet
Rates need two samples, so they appear a couple of seconds after you open the screen. Other users' and protected processes cannot be read; DiskPeek shows how many it skipped.

## EnvPeek says it cannot read a process
macOS lets MacPeek read the environment only of your own processes, and hides it for protected system programs. EnvPeek reports that as a failure rather than showing an empty list. Terminal-launched programs often differ from MacPeek's own environment, which is why **This app** and **A process** are labelled separately.

## SleepPeek's history takes a long time
**Load history** reads macOS's power log, which can take up to a minute. It runs only when you press it and stops if you leave the screen.

## NetPeek shows the Wi-Fi name as hidden
That is macOS. It withholds the network name from apps without Location access, and MacPeek does not ask for it. Signal, channel and rate still show.

## A ping to a DNS server was skipped
NetPeek pings IPv4 servers only, up to three. IPv6 servers are listed as skipped. No reply to a ping is not proof of an outage: some devices ignore pings.

## DNSPeek says a server timed out
The server did not answer within two seconds on that try. If only one server times out while the others answer, that is the one to fix or remove in **System Settings → Network → Details → DNS**.

## Launch at login doesn't stick
Run MacPeek from `/Applications`, then toggle it in settings. You can also manage it in System Settings → General → Login Items.

## macOS blocks the app
Download only from the official [download page](/download/) and verify the [checksum](/docs/installation/).

Still stuck? [Open an issue](https://github.com/mohitkap12-a11y/MACPeek/issues).
