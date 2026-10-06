# ProcessPeek

**Question:** What exactly is this process?

## What it shows
A searchable list of processes (yours by default). Open one for:

| Field | Source |
|---|---|
| PID, parent PID, user, uid, state, start time, running time, CPU, memory, "Started as" | `ps -axo pid,ppid,uid,user,state,lstart,etime,%cpu,rss,comm` |
| Command line | `ps -ww -o args= -p <pid>`, only when you open the process |
| Listening ports | PortPeek's `lsof` discovery filtered to the PID, only when you open the process. `lsof` runs without privileges and only sees your own processes' sockets, so for other users' processes ProcessPeek says "not visible" instead of "none" |
| Parent, children | derived from the parent PIDs in the same snapshot; click to jump |

`CPU` is the number `ps` prints (a decaying average, not an instantaneous reading) and is labelled "ps average". Memory is
resident size. "Started as" is `comm`: how the process was launched, which can be a relative path (`.build/…/MacPeek`), a login shell's
`-zsh`, or any name a process chose, so it is not guaranteed to be the binary's real location. It can contain spaces, so it
is parsed as the last column.

## Privacy
Command lines can contain secrets passed as arguments (tokens, passwords). They are read only for the process you open, shown
on screen, and never logged. Nothing is written to disk.

## Refresh
Reads when the screen opens and on ⌘R. There is no polling and no launcher summary.

## Limits
- It is read-only: ProcessPeek never ends or signals a process (use PortPeek or FileLockPeek for that, with their safety checks).
- Other users' processes are hidden unless you include them from the filter menu, and details for protected processes may be
  limited by macOS.
- It is deliberately not Activity Monitor: no live graphs, no per-thread data.

## Verified against
A real `ps` capture from a Mac mini (Mac14,3): `Tests/ProcessPeekKitTests/Fixtures/ps_sample.txt` (a 41-row slice, including
paths with spaces, a login shell `-zsh` and a parent with several children).
