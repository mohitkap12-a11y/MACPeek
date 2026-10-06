---
layout: ../../../layouts/Article.astro
title: "FileLockPeek: What Is Using This File? | MacPeek Docs"
description: "How to use FileLockPeek to find which process has a file or folder open, why a volume will not eject, and how to end the holder safely."
h1: "FileLockPeek"
section: docs
date: "2026-10-06"
---
**The question it answers:** what process is using this file?

## What you see
Choose a file or folder and FileLockPeek lists the processes that have it open. For each one: its name, PID, user and **how** it holds the path.

| Shown as | Meaning |
|---|---|
| Open · read / write / read/write | The process has the file open with that access |
| Locked | An advisory lock is held |
| Working dir | The path is the process's current folder. This blocks ejecting a volume or deleting a folder |
| Executable | The path is the program the process runs |
| Mapped | The path is memory-mapped, for example a loaded library |

## How to use it
1. Open **FileLockPeek** and click **Choose…**, drop a file or folder onto the popover, or paste a path and press Return.
2. Select a process to copy its PID or the path, **Reveal in Finder**, or **Kill Process**.
3. Press `⌘R` to scan again. MacPeek also rescans after a kill.

Killing uses the same safe steps as everywhere in MacPeek: see [killing safely](/docs/killing-processes/). After the process exits, MacPeek checks that it no longer holds the path, and says so if a different process now holds it. Other processes that already held the file may still hold it: they stay listed after the rescan, and the message says how many may remain.

## Good to know
- It **scans only when you ask**. A folder scan includes everything inside, so a large folder can take a moment. If macOS could not inspect part of the tree, you see "Results may be incomplete".
- Several processes can hold one file. Ending one does not release it from the others.
- Only your own processes are listed (see [permissions](/docs/permissions/)). "Nothing is holding it open" can mean another user's process has it. `sudo lsof` in Terminal shows everything.

## Privacy
Nothing leaves your Mac. See [find what process is using a file on Mac](/blog/how-to-find-what-process-is-using-a-file-on-mac/).
