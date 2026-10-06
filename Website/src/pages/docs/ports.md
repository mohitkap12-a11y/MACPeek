---
layout: ../../layouts/Article.astro
title: "Which Ports PortPeek Shows | PortPeek Docs"
description: "What PortPeek lists: listening TCP and UDP sockets on IPv4 and IPv6, wildcard and localhost addresses, and why some sockets are missing."
h1: "Ports PortPeek shows"
section: docs
date: "2026-10-06"
---
PortPeek lists sockets that are **listening** and visible to your user account.

| Kind | Shown | Notes |
|---|---|---|
| TCP listeners | Yes | State `LISTEN` only; established connections are hidden |
| UDP sockets | Yes, where bound to a port | Unbound or connected UDP sockets are skipped |
| IPv4 / IPv6 | Yes | `127.0.0.1`, `::1`, wildcard `*` and `::` |
| Same port on IPv4 and IPv6 wildcard | Merged | One row instead of two |

## Addresses
- `127.0.0.1:3000` / `[::1]:3000` — reachable only from your Mac.
- `*:3000` — listening on all interfaces, reachable from your network.

## What is not shown
Sockets owned by other users or system daemons running as root usually don't appear, because PortPeek never asks for administrator rights. `sudo lsof -nP -iTCP -sTCP:LISTEN` in Terminal shows everything.

Discovery uses the system `lsof` tool behind a replaceable interface; a native backend may follow. See [permissions](/docs/permissions/).
