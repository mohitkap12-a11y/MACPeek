---
layout: ../../layouts/Article.astro
title: "PortPeek Privacy: No Telemetry, No Account | PortPeek Docs"
description: "PortPeek does not send process, port or network information to a server. See exactly what the app reads and why it needs no network access."
h1: "Privacy"
section: docs
date: "2026-10-06"
---
> PortPeek does not send process, port or network information to a server.

- **No account.** Nothing to sign in to.
- **No telemetry or analytics** in the app.
- **No cloud backend**, no update pings, no crash reporting.
- **No network connection** is required or used for any feature.

## What PortPeek reads (locally)
- Which processes your user can see, and their name, PID, owner and start time.
- Local listening sockets: protocol, address and port.

This data is held in memory to draw the list and is not written to disk. The only thing stored is your preferences (refresh interval, toggles) in macOS user defaults.

## This website
The site is static. It sets no cookies and loads no third-party scripts. If privacy-friendly analytics are ever added, they will be documented here.

The code is open: [verify it yourself](https://github.com/mohitkap12-a11y/MACPeek).
