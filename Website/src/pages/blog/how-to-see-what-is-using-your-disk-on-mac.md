---
layout: ../../layouts/Article.astro
title: "Which App Is Using My Disk on Mac? | MacPeek"
description: "Find out which process is reading and writing your Mac's disk right now with Activity Monitor and Terminal tools, and how DiskPeek shows rates per process."
h1: "See Which App Is Using Your Disk on Mac"
section: blog
utility: diskpeek
date: "2026-10-06"
---
Your Mac feels sluggish, the drive is busy and nothing obvious is running. Here is how to see who is reading and writing.

## Activity Monitor
1. Open **Activity Monitor** and choose the **Disk** tab.
2. The **Bytes Written** and **Bytes Read** columns count what each process has done **since it started**. Sort by either one.

These are totals, not rates. A long-running app can top the list from last week's work, so a busy-now process can be hidden. Watch the columns over a few seconds to see which numbers are moving.

## Terminal
Overall device throughput, every 2 seconds (no process names):
```bash
iostat -d -w 2
```
Live file-system activity per process (needs administrator rights, and prints a lot):
```bash
sudo fs_usage -w -f filesys
```

## The usual suspects
- **Spotlight** (`mds`, `mdworker`) re-indexing after an update or a large copy.
- **Backups** (`backupd` for Time Machine) and cloud sync clients.
- **Photos and media analysis** (`photoanalysisd`) after you import pictures.
- **Browsers, Docker and build tools** writing caches and images.
- **Swap**: when memory is full, macOS writes to disk. Check the Memory tab.

## With DiskPeek
DiskPeek samples macOS's per-process disk counters while its screen is open and subtracts consecutive samples, so each row shows a **rate over the last interval** and a **total since you opened it**. The first sample is only a baseline, so rates appear a couple of seconds after you open it, and a restarted counter never produces a negative or absurd value. Other users' and protected processes cannot be read; DiskPeek shows how many it skipped. See the [DiskPeek docs](/docs/utilities/diskpeek/).

## Limits
Per-process counters show who is busy. They are not a byte-exact measure of the device, and cached reads may never reach the drive.
