---
layout: ../../../layouts/Article.astro
title: "SleepPeek: Why Your Mac Won't Sleep | MacPeek Docs"
description: "How to use SleepPeek to find the process keeping your Mac or display awake, read macOS's own sleep summary and load recent sleep and wake history."
h1: "SleepPeek"
section: docs
date: "2026-10-06"
---
**The question it answers:** why isn't my Mac sleeping?

## What you see
- A **headline** from macOS's own counters: something is keeping the Mac awake, only the display is held on, you are active, or nothing is blocking sleep.
- Each **blocker**: the process, its PID, the assertion type, its name and how long it has been held.
- macOS's own "sleep prevented by…" summary, quoted as reported, and your display and system sleep timers.
- **Other assertions** (user activity, USB and network wake) collapsed below.

## Fact versus inference
Every statement is labelled:
- **Reported by macOS**: read directly from the system.
- **Likely (inference)**: a common explanation from a small, conservative list. For example, a power-management daemon holding the display on is normal while the display is on. Unknown holders get facts only, never a guess.

## How to use it
1. Open **SleepPeek**. It refreshes every few seconds while the screen is open.
2. Find the blocker: a video call, a download, a backup or a development tool is the usual suspect. Open [ProcessPeek](/docs/utilities/processpeek/) to inspect it.
3. Press **Load history** to see recent sleep, wake and background-wake events with the reason exactly as macOS logged it, and the latest scheduled wake requests.

## Good to know
- **Load history is slower.** macOS can take up to a minute to produce its power log, so it runs only when you ask, and stops if you leave the screen.
- SleepPeek only reads. It never changes a power setting.
- Wake reasons are shown as macOS wrote them and are never reinterpreted.

## Privacy
Read-only; nothing is sent anywhere. See [Why won't my Mac go to sleep?](/blog/why-wont-my-mac-go-to-sleep/).
