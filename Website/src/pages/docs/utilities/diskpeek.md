---
layout: ../../../layouts/Article.astro
title: "DiskPeek: Which App Is Using the Disk? | MacPeek Docs"
description: "How to use DiskPeek to see which processes are reading and writing your disk right now, how the rates are measured and what the numbers can and cannot tell you."
h1: "DiskPeek"
section: docs
date: "2026-10-06"
---
**The question it answers:** which app is using my disk right now?

## What you see
The busiest processes by disk activity. Each row shows its **read and write rate** over the last sampling interval and its **total since you opened DiskPeek**. Order them by what is busy right now, or by the total.

## How to use it
1. Open **DiskPeek**. It takes a first sample, and rates appear after the second one, a couple of seconds later.
2. Watch the top rows while you reproduce the slowdown, then open [ProcessPeek](/docs/utilities/processpeek/) to inspect the process.
3. Leave the screen and sampling stops. Coming back starts from a fresh baseline, so a rate is never computed over the time the screen was closed.

## How it is measured
macOS keeps cumulative disk counters for every process. DiskPeek subtracts consecutive samples, every few seconds, only while its screen is open.
- A counter that goes *down* means the PID now belongs to a different process, so DiskPeek starts over for it. You never see negative or absurd values.
- A process that appears between samples started inside the interval, so everything it did counts.

## Good to know
- Other users' and protected processes cannot be read. DiskPeek shows how many it skipped.
- The numbers show who is busy. They are not a byte-exact audit of the drive.
- It is not a disk-space cleaner.

## Privacy
Read-only; nothing is stored or sent. See [permissions](/docs/permissions/).
