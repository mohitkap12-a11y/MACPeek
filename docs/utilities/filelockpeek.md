# FileLockPeek

**Question:** What process is using this file?

## What it shows
Choose a file or folder (**Choose…**, drag and drop, or paste a path) and FileLockPeek lists the processes that have it
open. For each process: name, PID, user, and **how** it holds the path:

| Shown as | Meaning (from lsof's `-F` fields: `f` descriptor, `a` access mode, `l` lock) |
|---|---|
| Open · read / write / read/write | an open file descriptor with access mode `r`, `w` or `u` |
| Locked | an advisory lock is held (the `l` field: `r R w W x X u`) |
| Working dir | the path is the process's current working directory (`cwd`), which blocks ejecting a volume or deleting a folder |
| Executable | the path is the process's program (`txt`) |
| Mapped | the path is memory-mapped, e.g. a loaded library (`mem`) |

Actions per holder: copy PID / process name, copy path, **Reveal in Finder**, and an optional **Kill Process**.

## How it works
`lsof -nP +c 0 -FpcLfaltn -- <file>` for a file, or `... +D <folder>` for a folder (recursive). The path must be absolute and
exist; it is passed as a separate argument, never through a shell. Output goes through `FileHolderParser` into
`[FileLockHolder]` grouped by process; MacPeek's own process is excluded. The UI depends on `FileLockDiscoveryProtocol`,
never on lsof output.

## Refresh
**Scans only when you ask** (Enter, Choose…, drop, or ⌘R) and once more after a kill. There is no polling and no
launcher summary, because folder scans are recursive. Leaving the screen cancels a running scan (a hung `lsof` is also
terminated after 30 s).

## Killing
Via the shared `ProcessTerminationService` (see [architecture](../architecture.md#safe-termination)) with a
`FileLockResource`: the holder and its identity (name + start time) are re-verified before SIGTERM; force kill is a separate,
explicit step that re-verifies again. Nothing is terminated by default. After the process exits, the file must no longer
be held by that PID; if another process now holds it, MacPeek says so instead of reporting success.

## Permissions
None to scan. `lsof` only lists processes owned by your user; others (including root daemons such as Spotlight's `mds`) are
not shown, and `sudo lsof` in Terminal shows everything. You can terminate only your own processes; root processes are
marked protected.

## Limits
- Folder scans include everything inside and can take a moment on large trees. If `lsof` warns that it could not inspect
  part of the tree, FileLockPeek shows "Results may be incomplete" instead of presenting the list as complete.
- Several processes can hold the same file. Ending one reports success when *that* process let go; the others (still listed after
  the rescan) keep holding it, and the banner says how many may remain.
- A file held open by a process of another user will show "Nothing is holding it open".
