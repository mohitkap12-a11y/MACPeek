# Alerts, the menu-bar readout and history

MacPeek's Peeks only work while you look at them. Three features work while you don't, all driven by one background
monitor (`VitalsMonitor`, logic in `Sources/VitalsKit`):

| Feature | Default | What it costs |
|---|---|---|
| **Alerts** | On | A few cheap reads every 5 s; a per-process scan (libproc) every 10 s |
| **History** (24 hours) | On | The same reads; sensors every 5 s; the GPU (`ioreg`) every 30 s; a small file saved every 5 min |
| **Menu-bar readout** | Off | The same reads at the refresh interval (at most every 5 s); the GPU every tick if shown |

With all three off the monitor does nothing at all: no timer, no reads. Nothing it produces leaves the Mac unless a device
of the Mac's own MacPeek Remote account asks for it (`vitals.history`, `alerts.recent`, see [remote.md](remote.md)).

## Alerts

| Alert | Rule (default) | Notes |
|---|---|---|
| Process stuck at high CPU | One process ≥ 90 % of a core for 5 min without a break | Per process (PID + start time), so a reused PID starts over |
| Process memory keeps growing | Footprint grew ≥ 2 GB within 15 min and never fell more than 10 % below its high on the way | Needs a nearly full window: a quick spike is not a leak |
| Memory pressure | Critical at once; warning (or worse) for 10 min | Kernel's `memorystatus_vm_pressure_level` |
| Swap growing | Swap used grew ≥ 2 GB within 30 min | `vm.swapusage` |
| Sustained network traffic | Download + upload ≥ 5 MB/s for 5 min | Physical interfaces only |
| Running hot | `ProcessInfo.thermalState` serious or critical | Critical is marked critical |

- One alert per episode: a condition that stays true never alerts twice. After it clears, the same alert waits an hour
  (`repeatMinutes`) before it may be raised again.
- **Don't Alert About This App** (in the notification, or on the alerts screen) adds the process name to an ignore list;
  Settings ▸ Alerts shows the list and clears it.
- Alerts appear in Notification Center (macOS asks for permission the first time one is raised) and under the bell in the
  launcher, which shows a dot for alerts not seen yet. The last 50 are kept across launches.
- Thresholds: CPU minutes, memory growth, network rate are pickers in Settings ▸ Alerts; every alert has its own switch.
- MacPeek's own process is never alerted about. Other users' processes (some macOS services) cannot be read and are not
  checked.

## Menu-bar readout

Settings ▸ Menu bar: any of **CPU**, **Memory**, **Network ↓↑**, **GPU** and **Temperature**, shown in a fixed order next to
the icon (or instead of it, unless Remote management is on: its dot must stay visible). Values use a 12 pt monospaced-digit
font so they stay readable and do not jump as they change; warning values are orange and critical values red (CPU and GPU
from 70 % / 90 %, memory by pressure, temperature from 85 °C / 95 °C). If the menu bar is full, macOS hides the item; see
[Hidden icon](#hidden-icon).

## History

24 hours of CPU, memory used, memory pressure (worst in each point), swap, network, GPU, the hottest CPU/SoC temperature
and whole-Mac power. Samples are averaged into 10-second points; points older than an hour are merged into one-minute
points; points older than a day are dropped (about 1,800 points, a few hundred KB). Saved to
`~/Library/Application Support/MacPeek/vitals-history.json` every 5 minutes and when MacPeek quits. Open it from the
launcher's chart button, the icon's right-click menu or Settings ▸ History (1, 6 or 24 hours). Turning History off deletes
the file.

## Hidden icon

macOS silently hides menu-bar items that do not fit (a full menu bar, or items that would sit under the notch). MacPeek
checks whether its item is visible (`NSStatusItem.isVisible`, its window's occlusion state and that it is on a screen):

- On the very first launch MacPeek opens its menu, so people see where it lives.
- If the icon is hidden, a small window says so, how to make room, and offers **Open MacPeek** and a link to
  [Ice](https://github.com/jordanbaird/Ice), a free, open-source menu-bar manager. It is shown at most once a week.
- Launching MacPeek again while it runs (Finder, Spotlight) opens it under its icon, or in a window when the icon is
  hidden.

## Sensors

Temperatures, fans and power are described in [CPUPeek ▸ Sensors](utilities/cpupeek.md#sensors). They are read through
interfaces Apple does not document, looked up at run time, read-only; a Mac that shares none simply shows no temperature.

## Code

- `Sources/VitalsKit`: `AlertEngine` / `AlertSettings` / `AlertEvent`, `VitalsHistory` / `VitalsHistoryFile`,
  `MenuBarReadout`, `ProcessGrouping`. UI-free and tested on Linux.
- `Sources/SensorsKit`: `SystemSensorReader` (HID temperatures, SMC fans/power/Intel temperatures), `SMCValue` decoding,
  `SensorClassifier`.
- `Sources/MacPeek/Support/VitalsMonitor.swift`: sampling and scheduling; `AlertNotifier.swift`: notifications and their
  buttons; `App/MenuBarController.swift`: the readout; `App/WelcomeController.swift`: first launch and hidden icon.
