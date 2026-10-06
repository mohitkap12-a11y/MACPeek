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

## Using DisplayPeek
1. Open **DisplayPeek**. It reads your display configuration when the screen opens (use `⌘R` to read again) and does nothing in the background.
2. Each connected display gets a card: panel resolution, the "looks like" desktop resolution, refresh rate, scaling, main/mirrored/online state, and anything else macOS reports.
3. Click the copy button on a card to copy its details, without serial numbers.

If macOS does not report a detail, DisplayPeek leaves it out rather than guessing.

## Using USBPeek
1. Open **USBPeek**. It reads when the screen opens (`⌘R` to read again) and does nothing in the background.
2. Devices are shown as a tree by USB bus, with hubs and the devices behind them. Click a device for its vendor, vendor:product ID, link speed, declared USB version and class, and copy them.
3. Thunderbolt / USB4 ports are listed below with their status and speed.

Serial numbers are never read. A device's link speed is what macOS negotiated, which is what to check when a fast drive seems slow.

## Using SleepPeek
1. Open **SleepPeek**. It shows what is keeping your Mac (or its display) awake, refreshing every few seconds while its screen is open.
2. Each blocker shows its process, PID, assertion type and how long it has been held. Statements are labelled **Reported by macOS** or **Likely (inference)**.
3. **Load history** reads recent sleep, wake and background-wake events from the power log. That can take up to a minute, so it only runs when you ask.

SleepPeek is read-only: it never changes a power setting.

## Using ProcessPeek
1. Open **ProcessPeek**. It reads the process list when the screen opens (`⌘R` to read again) and does nothing in the background.
2. Search by name, PID, user or path. The filter menu sorts by name, CPU, memory or PID and can include other users' processes (your own are shown by default).
3. Open a process to see its PID, user, start time, how long it has been running, CPU and memory, its executable path, its full command line, its listening ports, its parent and its children. Click the parent or a child to jump to it.

The command line and ports are read only for the process you open. Command lines can contain secrets passed as arguments, so they are shown on screen only. ProcessPeek is read-only: it never ends a process.

## Using DiskPeek
1. Open **DiskPeek**. It takes a first sample, and the rates appear after the second one, a couple of seconds later.
2. Each row is a process with its read and write rate over the last interval and the total since you opened DiskPeek. Order them by what is busy right now or by the total.
3. Leave the screen and sampling stops. Returning starts from a fresh baseline.

Every value is sampled and labelled that way. Other users' and protected processes cannot be read; DiskPeek shows how many it skipped.

## Using EnvPeek
1. Open **EnvPeek**. **This app** shows MacPeek's own environment, which is usually *not* the environment of your terminal.
2. Switch to **A process**, enter a PID (ProcessPeek shows PIDs) and press **Inspect** to read that process's environment. macOS only allows this for your own processes, and hides it for protected system processes.
3. Search names and values, copy a name, value or `NAME=value`, and open `PATH` entry by entry to spot duplicates, missing folders and relative entries.

Values that look like credentials are hidden until you press **Reveal**. Values stay on screen only: they are never logged or stored, and they are dropped from memory when you leave the screen.

## Keyboard and context menu
- Arrow keys move the selection; `⌘R` refreshes.
- Right-click a row to copy the port, PID or address, or open `http://localhost:<port>`.

## Settings
Launch at login, refresh interval (1–10 s), confirm before kill, notifications and appearance (system, light, dark). See [killing processes](/docs/killing-processes/) for how termination works.
