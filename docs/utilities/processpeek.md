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

## Kill Process
Open a process and press **Kill Process**. It uses the same shared safe-termination service as PortPeek and FileLockPeek:

1. **Confirm** (unless you turned confirmation off in Settings). Ending `loginwindow` or your user `launchd` always asks, because it
   ends your whole session.
2. **Re-check**: `ps` must still list the PID under the same name, and the kernel start time must match the one recorded when the
   list was read, so a PID that was **reused** by a different process is never signalled.
3. **SIGTERM** (a graceful request), then MacPeek waits for the process to exit and confirms it is gone.
4. If it ignores SIGTERM, MacPeek says so and offers an explicit **Force Kill** (SIGKILL), which re-checks identity again. There is
   never an automatic escalation.

Protected processes (PID 1, MacPeek itself, root-owned processes) cannot be killed; processes of other users say "Permission
required" and the kill is refused by macOS. MacPeek never elevates privileges.

## Privacy
Command lines can contain secrets passed as arguments (tokens, passwords). They are read only for the process you open, shown
on screen, and never logged. Nothing is written to disk.

## Refresh
Reads when the screen opens and on ⌘R. There is no polling and no launcher summary.

## Limits
- Ending a process is explicit and never automatic (see Kill Process above).
- Other users' processes are hidden unless you include them from the filter menu, and details for protected processes may be
  limited by macOS.
- It is deliberately not Activity Monitor: no live graphs, no per-thread data.

## Verified against
A real `ps` capture from a Mac mini (Mac14,3): `Tests/ProcessPeekKitTests/Fixtures/ps_sample.txt` (a 41-row slice, including
paths with spaces, a login shell `-zsh` and a parent with several children).

## Where it came from, what it has open, and whether ending it is safe
Opening a process now also shows:
- **The whole parent chain**, nearest first, each one clickable.
- **How it was started**, from `launchctl list` (your user's launchd domain): the launchd job it is, the app it is (apps opened
  from the Dock or Finder appear as `application.<bundle id>…`), or the nearest ancestor that is one. For a launchd job,
  `launchctl print gui/<uid>/<label>` adds its property list path and whether launchd **keeps it alive** (it would start again
  if ended). A process whose parent is launchd but which is not in your domain is labelled as a system or XPC service.
- **Open files**, on request (`lsof -n -P -w -p <pid> -F ftn`): working directory, binary, files, sockets and pipes, up to 300.
  macOS shows these only for your own processes.
- **Safe to end?**: "Probably safe", "Check before ending" or "Avoid", with the reasons (another user's or a core process,
  a session process, child processes, an app that should be quit from the app, a kept-alive launchd job). This is
  inference from what MacPeek can see and is labelled so; the Kill button and its safety checks are unchanged.
launchd job labels are passed to `launchctl print` only if they cannot be read as an option (no leading `-`, no `/` or
spaces). MacPeek never loads, unloads or changes a launchd job.
