---
layout: ../../layouts/Article.astro
title: "Why Won't My Mac Go to Sleep? Find the Sleep Blocker | MacPeek"
description: "Find what is keeping your Mac awake or waking it up using pmset: read sleep assertions, check the wake log, and fix the usual causes."
h1: "Why Won't My Mac Go to Sleep?"
section: blog
utility: sleeppeek
date: "2026-10-06"
---
When a Mac refuses to sleep, something is holding a **power assertion**: a request to stay awake. You can see who is asking.

## See what is blocking sleep
```bash
pmset -g assertions
```

Look at the assertions with a non-zero count, such as `PreventUserIdleSystemSleep` or `PreventUserIdleDisplaySleep`. Below the summary, macOS lists the owner, for example `pid 123(caffeinate)`, and often the reason it gave.

To see assertions being taken and released over time:

```bash
pmset -g assertionslog
```

## Check why it woke up
```bash
pmset -g log | grep -E "Wake|Sleep"
```

Wake entries usually include a reason, such as lid open, a power-button press or network activity.

## The usual causes
- **`caffeinate`** running in a Terminal tab. Stop it with Control-C in that tab.
- **Video, calls or screen sharing**, which keep the display and system awake on purpose.
- **Downloads, backups or syncing** in the background.
- **A browser tab or app** playing audio or holding a wake request.
- **Settings that allow wake-ups**, such as waking for network access. Look under **System Settings → Battery** (or **Energy** on a desktop Mac). The name and location vary by macOS version.
- **Connected devices** that send wake signals, such as some USB or Bluetooth accessories.

## Fixing it
1. Find the process in the assertions list.
2. Quit that app, or end whatever started it.
3. Run `pmset -g assertions` again to confirm the count has dropped.

## What this tells you, and what it does not
`pmset` reports what macOS recorded. A wake reason is a fact from the log; any explanation of *why* a device sent the signal is an inference.
