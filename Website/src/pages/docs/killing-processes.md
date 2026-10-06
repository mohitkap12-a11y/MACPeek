---
layout: ../../layouts/Article.astro
title: "How PortPeek Safely Kills a Process | MacPeek Docs"
description: "How PortPeek terminates the process behind a port: revalidation, SIGTERM first, port-release verification and an explicit force kill."
h1: "Killing processes safely"
section: docs
date: "2026-10-06"
---
Killing the wrong process is worse than not killing one, so PortPeek never signals a stale PID. Every MacPeek utility that can end a process uses this same shared safety logic.

## The sequence
1. **Re-scan** the port when you click Kill.
2. **Confirm** the port still exists and the same PID still owns it.
3. **Confirm identity**: process name and start time match what you saw (guards against PID reuse).
4. **SIGTERM** — a polite request to quit (`kill <pid>`).
5. **Wait** briefly and check the process exited.
6. **Verify the port is released.**
7. If the process is still alive, PortPeek shows a **Force Kill** option. Only if you confirm, it revalidates again and sends `SIGKILL`.

PortPeek never escalates to SIGKILL on its own, and refuses to signal PID 1 or itself.

## Possible outcomes
| Message | Meaning |
|---|---|
| Port freed | Process exited and the port is released |
| Already exited | The process was gone before the signal |
| Port already released | The process lives on, but no longer holds the port; nothing was killed |
| Target changed | A different process now owns the port; nothing was killed |
| Permission denied | Your user can't signal that process — see [permissions](/docs/permissions/) |
| Did not exit | SIGTERM was ignored; Force Kill is offered |
