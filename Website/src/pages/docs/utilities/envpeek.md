---
layout: ../../../layouts/Article.astro
title: "EnvPeek: Inspect Environment Variables | MacPeek Docs"
description: "How to use EnvPeek to inspect environment variables for MacPeek or a running process, walk through PATH entry by entry and keep credential values hidden."
h1: "EnvPeek"
section: docs
date: "2026-10-06"
---
**The question it answers:** what environment variables does this environment see?

## Two sources, always labelled
- **This app:** MacPeek's own environment. A menu-bar app launched from Finder or at login usually sees far fewer variables than your terminal, and EnvPeek says so.
- **A process:** the environment of one process whose PID you enter (ProcessPeek shows PIDs). macOS allows this only for your own processes, and hides it for protected system binaries. A failed read is reported as a failure, never shown as an empty environment.

The source is shown at the bottom of the screen so a per-process value is never mistaken for a global one.

## How to use it
1. Open **EnvPeek**. Choose **This app** or **A process**; for a process, enter its PID and press **Inspect**.
2. Search names and values, and copy a name, a value or `NAME=value`.
3. Open `PATH`, `MANPATH` and similar variables **entry by entry**. EnvPeek flags duplicates (only the first can be used), folders that do not exist, relative entries and empty entries (which mean "the current directory").

## Privacy
- Values that look like credentials (names containing TOKEN, SECRET, PASSWORD, API_KEY and similar) are **hidden until you press Reveal**. That is a convenience heuristic, not a guarantee.
- Values are never logged or written to disk. When you leave the screen they are dropped from memory and anything revealed is hidden again.

## Good to know
- EnvPeek does not run your login shell, because that would run your startup files. To see what a terminal sees, inspect that terminal's shell by PID.
- It shows the environment a process **started with**, not variables it set later.
