---
layout: ../../layouts/Article.astro
title: "Check MacBook Battery Health and Cycle Count | MacPeek"
description: "Check your MacBook's battery health, maximum capacity and cycle count in System Settings, System Information or Terminal, and what the numbers mean."
h1: "How to Check MacBook Battery Health"
section: blog
utility: batterypeek
date: "2026-10-06"
---
## In System Settings
Open **System Settings → Battery** and look for **Battery Health**. On recent macOS versions it shows the battery's **Maximum Capacity** and a condition such as Normal or Service Recommended.

## Cycle count in System Information
1. Hold **Option** and open the **Apple menu**, then choose **System Information**.
2. Choose **Power** in the sidebar.
3. Under **Health Information** you will see **Cycle Count** and **Condition**.

## In Terminal
```bash
system_profiler SPPowerDataType | grep -E "Cycle Count|Condition|Maximum Capacity"
pmset -g batt
```

The first command prints the health fields where your macOS version reports them. `pmset -g batt` shows the current charge, whether it is charging and an estimate of the time remaining.

## What the numbers mean
- **Cycle count:** one cycle is a full charge's worth of use, not one plug-in. Apple publishes the rated cycle count for each Mac model, so look yours up.
- **Maximum capacity:** how much charge the battery can hold now compared with when it was new. It is an estimate, and it drifts a little between readings.
- **Condition:** Apple's own summary of whether the battery needs service.

## Looking after the battery
Keep the Mac out of extreme heat, avoid leaving it at 100% on a hot desk for weeks, and let macOS's Optimized Battery Charging do its job if it is on.

## Limits
Different Macs and macOS versions expose different fields. If a value is missing, macOS is not reporting it. Treat precise-looking degradation numbers from third-party tools with caution.
