---
layout: ../../../layouts/Article.astro
title: "ProcessPeek: Inspect and Kill a Process | MacPeek Docs"
description: "How to use ProcessPeek to search running processes, see their command line, ports, parent and children, and end one safely with graceful and force kill."
h1: "ProcessPeek"
section: docs
date: "2026-10-06"
---
**The question it answers:** what exactly is this process?

## What you see
A searchable list of processes (yours by default). Open one for:

| Field | Meaning |
|---|---|
| PID, parent PID, user, state | Identity and status |
| Started, running for | When it started and how long it has run |
| CPU, memory | The `ps` average and resident memory. Not live graphs |
| Started as | How it was launched. It can be a relative path or any name the process chose, so it is not guaranteed to be the real location |
| Command line | The full command with its arguments, read only for the process you open |
| Listening ports | Your own processes only. Others show "not visible" instead of "none" |
| Parent and children | Click one to jump to it |

## How to use it
1. Open **ProcessPeek**. It reads the list when the screen opens (`⌘R` to read again) and does nothing in the background.
2. Search by name, PID, user or path. The filter menu sorts by name, CPU, memory or PID and can include other users' processes.
3. Open a process to inspect it, and copy what you need.

## Kill Process
Open a process and press **Kill Process**.
1. MacPeek **confirms** (you can turn this off in Settings). Ending `loginwindow` or your user `launchd` always asks, because it ends your session.
2. It **re-checks** that the PID is still the same process, by name and start time, so a reused PID is never hit.
3. It asks the process to quit (**SIGTERM**), waits, and confirms it exited.
4. If it ignores the request, you can choose an explicit **Force Kill**. It re-checks again first. Nothing escalates on its own.

Protected processes (PID 1, MacPeek itself, root-owned) cannot be ended. Processes of other users say "Permission required". MacPeek never elevates privileges. Details: [killing safely](/docs/killing-processes/).

## Privacy
Command lines can contain secrets passed as arguments. They are read only for the process you open, shown on screen, and never logged or stored.
