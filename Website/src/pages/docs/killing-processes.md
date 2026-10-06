---
layout: ../../layouts/Article.astro
title: "How MacPeek Safely Kills a Process | MacPeek Docs"
description: "How MacPeek ends a process from PortPeek, FileLockPeek or ProcessPeek: revalidation, SIGTERM first, release verification and an explicit force kill."
h1: "Killing processes safely"
section: docs
date: "2026-10-06"
---
Killing the wrong process is worse than not killing one, so MacPeek never signals a stale PID. **PortPeek, FileLockPeek and ProcessPeek** all use this same shared safety logic; the steps below describe it from PortPeek, and the table at the end shows what each utility verifies.

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

## What each utility verifies
| Utility | After SIGTERM, MacPeek confirms |
|---|---|
| PortPeek | The process exited and the port is released |
| FileLockPeek | The process exited and the file is no longer held by that PID. If another process now holds it, MacPeek says so |
| ProcessPeek | The process exited. A zombie that has already ended counts as gone |

In every case the PID must still be the same process (name and start time) before any signal is sent, and Force Kill is a separate step you choose. Ending `loginwindow` or your user `launchd` from ProcessPeek always asks first, because it ends your session. See also [permissions](/docs/permissions/) and [ProcessPeek](/docs/utilities/processpeek/).
