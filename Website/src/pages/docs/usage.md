---
layout: ../../layouts/Article.astro
title: "How to Use PortPeek | PortPeek Docs"
description: "Learn how to browse ports, search by port, process or PID, inspect a process and kill it from the PortPeek menu bar popover."
h1: "Using PortPeek"
section: docs
date: "2026-10-06"
---
1. **Click the menu-bar icon.** PortPeek scans immediately and then refreshes every 2 seconds while the popover is open.
2. **Browse** the scrollable list of listening ports: port, process name, PID and protocol.
3. **Search.** Type a port (`3000`, or just `30`), a process name (`node`), a PID or an address. Multiple words narrow the result (`node 5173`).
4. **Select a row** to expand it: process, PID, protocol, address, state, user and whether you can terminate it.
5. **Kill Process.** PortPeek confirms (configurable), re-checks the target and asks the process to quit gracefully.
6. **Verify.** On success you see "✓ Port 3000 freed". PortPeek confirms the process exited and the port is released before it says so.

## Keyboard and context menu
- Arrow keys move the selection; `⌘R` refreshes.
- Right-click a row to copy the port, PID or address, or open `http://localhost:<port>`.

## Settings
Launch at login, refresh interval (1–10 s), confirm before kill, notifications and appearance (system, light, dark). See [killing processes](/docs/killing-processes/) for how termination works.
