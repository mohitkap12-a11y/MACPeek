# DiskPeek

**Question:** Which app is using my disk right now?

## What it shows
**Storage**: each local drive's capacity and the space available on it, with a bar and a "Low space" badge under 10 %
available. "Available" is the figure Finder shows: free space plus space macOS frees by itself when something needs it (caches,
local snapshots, iCloud copies), and DiskPeek says how much of it is that kind of space. Storage uses decimal units
(1 GB = 1000³ bytes), as Finder does.

**Activity**: the busiest processes by disk I/O, as read and write **rates over the last sampling interval** and **totals since you opened
DiskPeek**. Every value is sampled and labelled that way.

## How it works
Drive capacity comes from Foundation's volume information (`mountedVolumeURLs` with `.skipHiddenVolumes`, then
`volumeTotalCapacity`, `volumeAvailableCapacity` and `volumeAvailableCapacityForImportantUsage`). Only local, browsable volumes
are listed; network volumes are skipped so an unresponsive server cannot stall the screen. At most four drives are shown.

Per-process counters come from `proc_pid_rusage(RUSAGE_INFO_V4)` (`ri_diskio_bytesread`, `ri_diskio_byteswritten`), the
cumulative bytes macOS counts for each process since it started. `DiskIOSampler` subtracts consecutive samples:

- The **first sample is a baseline only**; rates appear after the second sample.
- A counter that **goes down** means the PID now belongs to a different process, so it starts a new baseline: no negative or
  absurd values.
- A process that appears **between samples** started inside the interval, so everything it has done counts toward that interval.
- Processes that exit disappear.

## Sampling
Every `max(refresh interval, 2)` seconds, **only while the screen is open**. Leaving the screen stops the timer and discards
the baseline, so coming back never shows a rate computed over the time the screen was closed. Drive capacity is read when the
screen opens and every 30 seconds after, off the main thread. The counters are read off the
main thread. There is no launcher summary.

## Limits
- Other users' and protected processes cannot be read by `libproc`; DiskPeek shows how many it skipped.
- The counters are what macOS keeps per process; they are an indication of who is busy, not a byte-exact audit of the device.
- It is not a disk-space cleaner and never looks inside your folders: there is no "what is using my space" scan, because
  reading many folders (Mail, Messages, other apps' data) would need Full Disk Access.

## Verified against
Drive capacity arithmetic and ordering are unit-tested; the live reader test runs in CI on macOS (the startup disk is listed
first). **Not yet verified on hardware:** that the APFS Data volume stays hidden (it should not appear next to Macintosh HD), and
external and removable drives. The sampler is unit-tested with synthetic counters (rates, PID reuse, new and exited processes). The `libproc` reader runs in
CI on macOS (the live test confirms the current process is readable); a Linux `/proc/<pid>/io` fallback exists only so the
logic can be tested on Linux.
