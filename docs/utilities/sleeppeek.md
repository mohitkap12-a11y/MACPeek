# SleepPeek

**Question:** Why isn't my Mac sleeping?

## What it shows
- A **headline** from macOS's own system-wide assertion counters: something is keeping the Mac awake, only the display,
  you are active, or nothing is blocking sleep.
- Each **blocking assertion** (`PreventUserIdleSystemSleep`, `PreventSystemSleep`, `PreventUserIdleDisplaySleep` and the legacy
  `NoIdleSleepAssertion` / `NoDisplaySleepAssertion`): process, PID, type, name and how long it has been held.
- macOS's own **"sleep prevented by …"** summary from `pmset -g`, quoted as reported.
- The display and system sleep timers.
- **Other assertions** (user activity, kernel assertions for USB devices and network wake) collapsed.
- On request, **recent sleep, wake and background-wake events** with the "due to …" reason exactly as logged, and the most
  recent scheduled wake requests.

## Fact versus inference
Every statement is labelled:
- **Reported by macOS**: read directly from `pmset` output.
- **Likely (inference)**: a common explanation from a small, conservative table (for example powerd's "Prevent sleep while display
  is on" is normal while the display is on). Unknown holders get facts only, never a guess.
Wake reasons are never interpreted: they are shown as macOS wrote them.

## How it works
`pmset -g assertions` and `pmset -g` for the snapshot (cheap; refreshed every few seconds while the screen is open), and
`pmset -g log` for history. `pmset -g log` took longer than 20 seconds on a real Mac, so it only runs when you press
**Load history**, has a 90-second limit, and is cancelled if you leave the screen. SleepPeek only reads: it never runs `pmset`
with a write flag and never changes a setting. `pmset -g assertionslog` is deliberately not used because it streams forever.

## Launcher summary
"N blockers", "Display held awake" or "No blockers", from one `pmset -g assertions` read when the popover opens.

## Verified against
A Mac mini (Mac14,3). Fixtures: `Tests/SleepPeekKitTests/Fixtures/` (assertions, `pmset -g`, 60 lines of the power log).
Sleep/wake lines on a battery-powered MacBook ("Using BATT", lid events) follow the same format but were not available for
verification; the parser handles the documented `Using AC|Batt|UPS` suffix and is covered by a synthetic test.
