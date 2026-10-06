# EnvPeek

**Question:** What environment variables does this environment see?

## Two sources, always labelled
- **This app**: MacPeek's own environment (`ProcessInfo`). A menu-bar app launched from Finder or at login usually sees far
  fewer variables than your terminal, and EnvPeek says so next to the list.
- **A process**: the environment of one process whose PID you enter, read with `sysctl(KERN_PROCARGS2)`. macOS only allows
  this for processes owned by your user, and hides the environment of system-protected binaries. (`ps eww` shows nothing for
  those on current macOS: a capture of it for `/bin/sleep` printed no environment.) Failures are reported as such, never as an
  empty environment.

The source is shown in the footer of the screen, so a per-process value is never mistaken for a global one.

## What you can do
Search names and values; copy the name, the value or `NAME=value`; open `PATH`, `MANPATH` and similar variables **entry by
entry**, with notes for duplicates (only the first can be used), folders that do not exist, relative entries and empty entries
(which mean "the current directory").

## Privacy
- Values that look like credentials (names containing TOKEN, SECRET, PASSWORD, CREDENTIAL, PRIVATE, COOKIE, API_KEY, or ending
  in `_KEY`/`_PASS`) are hidden until you press **Reveal**. This is a convenience heuristic, not a guarantee.
- Values are **never logged** (the log only records that a read failed), never written to disk, and are dropped from memory,
  with anything revealed re-hidden, when you leave the screen.

## Limits
- It does not run your login shell (that would execute your shell startup files), so it cannot show "what a new terminal would
  see"; inspect a running shell's PID instead.
- `KERN_PROCARGS2` shows the environment a process **started with**, not variables it set later.

## Verified against
The `KERN_PROCARGS2` buffer parser is unit-tested with synthetic buffers, including malformed ones. The readers are exercised
in CI on macOS and Linux against the test process itself.
