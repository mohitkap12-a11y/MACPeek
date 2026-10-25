# MemoryPeek

**Question:** Is my Mac actually running out of memory?

## What it shows
- **Memory pressure** first, as the headline: Normal, Warning or Critical. Pressure, not "free memory", says whether the Mac
  is short of RAM, because macOS keeps spare memory busy with cached files on purpose. A plain-language reading explains what
  the numbers mean; when macOS does not report pressure, MemoryPeek says so instead of guessing.
- **How memory is used**, split the way Activity Monitor's Memory tab splits it:

| Row | Computed as (`host_statistics64(HOST_VM_INFO64)` pages × page size) |
|---|---|
| App memory | internal pages − purgeable pages |
| Wired (kept by macOS) | wired pages |
| Compressed | pages the compressor occupies |
| Used | app + wired + compressed |
| Cached files | external (file-backed) pages + purgeable pages |
| Free | installed − used − cached files |

- **Moved to disk (swap)** from `vm.swapusage`.
- **Using the most memory**: the 15 processes with the largest memory footprint (`ri_phys_footprint` from
  `proc_pid_rusage`), which is the figure Activity Monitor's Memory column shows (ProcessPeek shows resident size instead).

Memory is shown in binary units (1 GB = 1024³ bytes), as Activity Monitor does.

## Sources
| Value | Source |
|---|---|
| Installed memory | `sysctl hw.memsize` |
| Page counts | `host_statistics64(HOST_VM_INFO64)`, page size `vm_kernel_page_size` |
| Swap | `sysctl vm.swapusage` |
| Memory pressure | `sysctl kern.memorystatus_vm_pressure_level` (1 normal, 2 warning, 4 critical; anything else is "not reported") |
| Per-process footprint | `proc_pid_rusage(RUSAGE_INFO_V4)` |

## Refresh
Every `max(refresh interval, 2)` seconds, **only while the screen is open**. Leaving the screen stops the timer, and coming
back starts from a fresh reading instead of showing the last visit's figures. The reads run
off the main thread, and leaving the screen also stops a process scan that is already running. The launcher
ring (memory in use, e.g. "71%" and "17 / 24 GB"; red when pressure is critical) is one read of the system numbers when
the popover opens, without a process scan.

## Permissions
None. Every value above is readable by a normal user. libproc refuses other users' processes, which include some macOS services
(such as WindowServer), so they are counted but not listed; the footer says how many.

## Limits
- It explains memory; it never "frees" or "cleans" it. There is no purge button, by design.
- The Activity Monitor split is the commonly documented mapping of the kernel's page counters; Activity Monitor's exact
  arithmetic is not public, so small differences are possible.

## Verified against
The breakdown, pressure mapping, plain-language reading and process ordering are unit-tested with synthetic page counts. The
live reader test runs in CI on macOS. **Not yet verified on hardware:** that `kern.memorystatus_vm_pressure_level` is readable
without privileges on every supported macOS version (if it is not, pressure shows as not reported), and how closely the split
matches Activity Monitor on Apple silicon and Intel Macs.
