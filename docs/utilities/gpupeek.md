# GPUPeek

**Question:** How busy are my GPU and Neural Engine, and who is using them?

## What it shows
- Per GPU: how busy it is (`Device Utilization %`), and on Apple GPUs the renderer and tiler utilization, the number of GPU
  cores, the memory the GPU is using right now (`In use system memory`) and what its driver has set aside
  (`Alloc system memory`). On Apple silicon this memory is part of the Mac's unified memory, and says so. On Intel Macs with
  a separate GPU, VRAM used and total where the driver reports them.
- A "since opened" chart of GPU load.
- **Processes using the GPU**: every process with a GPU connection (`IOAccelerator` user client), and the share of GPU time
  each used since the last reading where the driver counts it (`AppUsage` → `accumulatedGPUTime`).
- On Apple silicon, **Neural Engine, GPU and CPU power** in watts.

## The Neural Engine
macOS publishes no Neural Engine utilization to apps. `powermetrics` shows it, but only to administrators, and MacPeek
never asks for administrator rights. GPUPeek shows the Neural Engine's **power draw** instead, from the same energy counters
`powermetrics` uses: 0 W means idle, and the value rises with work. The screen says this in plain words.

## How it works
- `ioreg -r -d 2 -c IOAccelerator -a -w0` (a property list): read-only, no permission.
- Power: IOReport's `Energy Model` channels (`CPU Energy`, `GPU Energy`, `ANE…`), two samples apart, converted from mJ/µJ/nJ.
  IOReport is **not a public framework**: `libIOReport.dylib` is loaded at run time and every function is looked up by name.
  If any is missing (or on an Intel Mac) GPUPeek says power is unavailable; nothing else changes. Only the energy group is
  subscribed to, and nothing is written.
- Sampled every *refresh interval* (at least 1 s) only while the screen is open; per-process shares and power appear from
  the second reading. History is dropped when you leave. The launcher shows "GPU 12%" from one `ioreg` read.

## Fact versus inference
Utilization and memory are the driver's own numbers. Per-process GPU share is computed by MacPeek from the driver's counters.
Neural Engine "working/idle" is MacPeek's reading of its power draw (≥ 10 mW = working).

## Verified against
**Not yet verified on a Mac.** The `ioreg` keys and the IOReport channel names follow what open-source tools (for example
`macmon` and `asitop`) document; fixtures in `Tests/GPUPeekKitTests/Fixtures/` are constructed. `scripts/capture-fixtures.sh`
captures the real `ioreg` output. Check on the oldest and newest supported macOS and on an Intel Mac before release.
