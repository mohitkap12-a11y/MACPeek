---
layout: ../../layouts/Article.astro
title: "How to Find and Kill a Process on Mac | MacPeek"
description: "Find a running process on your Mac and end it safely: Activity Monitor, ps, pgrep, kill and killall, plus how ProcessPeek shows the details first."
h1: "Find and Kill a Process on Mac"
section: blog
utility: processpeek
date: "2026-10-06"
---
An app is frozen, a fan is spinning or something is eating memory. Here is how to find the process and end it without hitting the wrong one.

## Activity Monitor
1. Open **Activity Monitor** (Spotlight → "Activity Monitor").
2. Type the name in the search box, or sort by **% CPU** or **Memory**.
3. Select the process and click the **✕** button, then choose **Quit**. Choose **Force Quit** only if Quit does nothing.

## Terminal: find the PID
```bash
pgrep -fl chrome
ps aux | grep -i chrome
```
`pgrep -fl` prints the PID and command line of every match. With `ps aux | grep`, ignore the line for `grep` itself.

To see details for one process:
```bash
ps -o pid,ppid,user,etime,%cpu,rss,command -p 12345
```

## Terminal: end it
```bash
kill 12345        # SIGTERM: asks the process to quit and clean up
kill -9 12345     # SIGKILL: ends it immediately, no cleanup
killall Safari    # every process with that exact name
```
Always try plain `kill` first. `kill -9` cannot save state and can leave lock files or half-written data behind. Be careful with `pkill -f pattern` and `killall`: they match more than you may expect.

## The PID reuse trap
A PID is only a number. If a process exits and a new one starts, the new one can get the same PID. Between "I looked up the PID" and "I ran kill", the number may belong to something else. Check again right before you kill, or use a tool that does it for you.

## Why some kills fail
You can only signal processes owned by your own user. System daemons run as root, and `kill` says "Operation not permitted". Ending those is rarely a good idea; do it deliberately with `sudo`.

## With ProcessPeek
ProcessPeek lists your processes with their command line, parent, children and listening ports, so you can see what a process *is* before you end it. **Kill Process** confirms, re-checks that the PID is still the same process, asks it to quit, and only then offers an explicit **Force Kill**. See the [ProcessPeek docs](/docs/utilities/processpeek/) and [how MacPeek kills safely](/docs/killing-processes/).
