---
layout: ../../layouts/Article.astro
title: "Mac Port Manager: See and Free Ports from the Menu Bar | MacPeek"
description: "What a good Mac port manager should do: list listening ports, show the owning process, kill safely and stay private. Compare Terminal, Activity Monitor and PortPeek."
h1: "A Mac Port Manager That Lives in Your Menu Bar"
section: blog
utility: portpeek
date: "2026-10-06"
---
macOS has no built-in screen that answers "which app is using port 5432?" Here are your options.

## Options compared
| Tool | Shows ports | Maps to process | Kills | Friction |
|---|---|---|---|---|
| Terminal (`lsof`, `kill`) | Yes | Yes | Yes | Commands to remember |
| Activity Monitor | Not by port | Yes | Yes | Hard to find by port |
| Network Utility | Removed in recent macOS | – | – | – |
| PortPeek | Yes | Yes | Yes | One click |

## What a port manager should do
1. List listening TCP and UDP ports (IPv4 and IPv6).
2. Search by port, process name or PID.
3. Kill safely: graceful first, never a stale PID.
4. Explain permission limits instead of failing silently.
5. Respect privacy: no account, no telemetry.

## PortPeek
PortPeek is a free, open-source utility inside MacPeek, a native menu-bar app, built around exactly that list. It deliberately **isn't** a system monitor — no CPU graphs, no clutter. See the [PortPeek page](/utilities/portpeek/), [usage docs](/docs/usage/) and [how killing works](/docs/killing-processes/).
