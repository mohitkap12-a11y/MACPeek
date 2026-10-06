---
layout: ../../layouts/Article.astro
title: "How to Check Monitor Refresh Rate on Mac | MacPeek"
description: "Find your Mac's real display resolution and refresh rate in System Settings or Terminal, and what to check when an external monitor won't run at 120 Hz."
h1: "How to Check Monitor Refresh Rate on Mac"
section: blog
utility: displaypeek
date: "2026-10-06"
---
Paid for a 120 Hz or 144 Hz monitor and not sure your Mac is actually driving it that fast? Here is how to see what each display is really running.

## In System Settings
1. Open **System Settings → Displays**.
2. Select the display you want to check.
3. Look for the **Refresh Rate** menu. It lists the rates macOS offers for that display over the current connection.

If there is no Refresh Rate menu, macOS is only offering one rate for that display on that connection.

## In Terminal
```bash
system_profiler SPDisplaysDataType
```

This lists each display with its resolution and, on recent macOS versions, a line such as `UI Looks like: … @ 60 Hz` that includes the refresh rate. The exact wording varies between macOS versions.

## If the rate is lower than expected
- **The cable or adapter is the usual culprit.** Older HDMI versions and some USB-C adapters cannot carry high resolution at high refresh rates. Try a cable or port rated for your target resolution and rate, such as DisplayPort 1.4 or HDMI 2.0 and newer.
- **Check the monitor's own menu.** Some monitors have a setting that limits the refresh rate or the input mode.
- **Try a different port.** On a laptop, ports can differ in capability.
- **Resolution and scaling interact.** A very high resolution may only be offered at lower refresh rates over a given link.

## What the numbers do not tell you
macOS shows the mode in use, not the cable. If a detail is not exposed (for example the exact cable type), it simply is not shown; treat guesses about it with caution.
