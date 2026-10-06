---
layout: ../../layouts/Article.astro
title: "How to Use MacPeek | MacPeek Docs"
description: "Learn the MacPeek launcher: open a utility, search, go back, change settings, and use PortPeek to find and free a port."
h1: "Using MacPeek"
section: docs
date: "2026-10-06"
---
## The launcher
1. **Click the menu-bar icon.** MacPeek opens a compact popover listing the utilities you have switched on.
2. **Search** the launcher by name or by the question a utility answers.
3. **Click a utility** to open it inside the same popover. Use the **back** button (or `⌘[`) to return to the launcher.
4. The **gear** opens Settings. **Manage utilities** (launcher footer or Settings) lists every utility with an on/off switch: see [managing utilities](/docs/managing-utilities/).

When the popover opens, enabled utilities may take one quick snapshot to fill in the launcher's one-line summaries (for example PortPeek's port count). **Continuous refreshing happens only while a utility's own screen is open.** A switched-off utility does no work at all. The popover always reopens on the launcher.

## Using PortPeek
1. Open **PortPeek**. It scans immediately and refreshes every 2 seconds while its screen is open.
2. **Browse** the scrollable list of listening ports: port, process name, PID and protocol.
3. **Search.** Type a port (`3000`, or just `30`), a process name (`node`), a PID or an address. Multiple words narrow the result (`node 5173`).
4. **Select a row** to expand it: process, PID, protocol, address, state, user, and whether you can terminate it. Copy buttons copy the port, PID, process or address.
5. **Kill Process.** MacPeek confirms (configurable), re-checks the target and asks the process to quit gracefully.
6. **Verify.** On success you see "✓ Port 3000 freed". MacPeek confirms the process exited and the port is released before it says so.

## Using FileLockPeek
1. Open **FileLockPeek** and choose a file or folder: click **Choose…**, drop one onto the popover, or paste a path and press Return.
2. MacPeek lists the processes that have it open, and how: open for reading or writing, locked, working directory, executable or memory-mapped.
3. Select a process to copy its PID or the path, reveal the item in Finder, or **Kill Process** (same safe checks as PortPeek; nothing is ever terminated for you).

FileLockPeek scans **only when you ask**, and a folder scan includes everything inside it, so large folders can take a moment.

## Keyboard and context menu
- Arrow keys move the selection; `⌘R` refreshes.
- Right-click a row to copy the port, PID or address, or open `http://localhost:<port>`.

## Settings
Launch at login, refresh interval (1–10 s), confirm before kill, notifications and appearance (system, light, dark). See [killing processes](/docs/killing-processes/) for how termination works.
