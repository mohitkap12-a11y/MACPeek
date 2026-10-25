# CPUPeek

**Question:** What is making my Mac slow or hot right now?

## What it shows
- A headline ("CPU is mostly idle", "CPU is busy. Busiest: …", "Your Mac is running hot") and one bar per logical core.
- **In use**: share of all cores busy over the last interval, split into apps (user + nice) and macOS (system).
- **Chip** and **Cores**: the chip name and, on Apple silicon, how many performance and efficiency cores macOS reports. The
  per-core bars are not labelled by core type, because macOS does not document which core number is which type.
- **Load average** (1, 5, 15 minutes).
- **Temperature**: macOS's thermal state (`ProcessInfo.thermalState`). "High" and "Critical" mean macOS may be slowing the CPU
  to cool down. It is a state macOS reports, not a temperature reading.
- **Using the most CPU**: the 20 busiest processes over the last interval. 100 % is one core fully busy, as in Activity
  Monitor, so a busy multi-threaded app can show more than 100 %.

## How it works
- Per-core use comes from the difference between two `host_processor_info(PROCESSOR_CPU_LOAD_INFO)` readings. The tick
  counters are 32-bit and wrap; differences use wrapping arithmetic.
- Per-process use comes from `proc_pid_rusage(RUSAGE_INFO_V4)` (`ri_user_time + ri_system_time`), converted from Mach time
  units with `mach_timebase_info` (they are not nanoseconds on Apple silicon). `ProcessCPUSampler` subtracts consecutive samples
  with the rules DiskPeek uses (`ProcessCounterSampler`): the first sample is a baseline, a PID with a different start time
  is a different process, a process that appears between samples counts in full only if its age shows it started inside the
  interval (a long-running process that could not be read last time starts a new baseline instead of showing an absurd
  percentage), and a counter that goes down reports nothing.
- If the core count changes between two readings, CPUPeek shows nothing for that interval rather than the previous figures.
- This is more current than ProcessPeek's CPU column, which is `ps`'s decaying average.

## Sampling
At the refresh interval set in Settings (1 to 10 seconds), **only while the screen is open**. The first sample is a baseline, so
the second follows after 0.4 s and values appear almost at once. Leaving the screen stops the timer and discards
the baseline, so coming back never shows use computed over the time the screen was closed. Reads run off the main thread. The
launcher ring (overall use, with the load average under it, or "running hot" and red when macOS reports a high thermal
state) updates at the refresh interval while the launcher is on screen, from consecutive readings (two readings a third of
a second apart when there is no recent one); it stops when you open a utility or close the menu. A launcher reading from the
last 15 seconds is the baseline when CPUPeek opens, so overall use shows immediately.

## Permissions
None. libproc refuses other users' processes, which include some macOS services (such as WindowServer and kernel_task), so they
are counted but not listed; the footer says how many. Overall and per-core use always include them.

## Limits
- No GPU figures yet (planned separately: overall GPU use only, because a per-app breakdown needs administrator rights).
- No history graph and no menu-bar readout: CPUPeek does no work unless its screen is open.

## Verified against
Per-core and per-process arithmetic (wrapping counters, reused PIDs, new processes) is unit-tested with synthetic counters. The
live reader tests run in CI on macOS and, through `/proc/stat`, on Linux. **Not yet verified on hardware:** the
`hw.perflevel*` core counts and names on each Apple silicon generation, and the Mach time conversion against Activity Monitor
on an Apple silicon Mac.
