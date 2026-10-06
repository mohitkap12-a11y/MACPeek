---
layout: ../../layouts/Article.astro
title: "PortPeek Troubleshooting | PortPeek Docs"
description: "Fixes for PortPeek problems: a port is missing, Kill does nothing, Launch at login fails, or macOS blocks the app."
h1: "Troubleshooting"
section: docs
date: "2026-10-06"
---
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

## Launch at login doesn't stick
Run PortPeek from `/Applications`, then toggle it in settings. You can also manage it in System Settings → General → Login Items.

## macOS blocks the app
Download only from the official [releases page](https://github.com/mohitkap12-a11y/PortPeek/releases/latest) and verify the [checksum](/docs/installation/).

Still stuck? [Open an issue](https://github.com/mohitkap12-a11y/PortPeek/issues).
