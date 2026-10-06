# Architecture

```text
                         MACPEEK
                            |
            +---------------+----------------+
            |                                |
       Menu Bar Shell                    Shared Core
   (Sources/MacPeek)               (Sources/MacPeekCore)
            |                                |
  Launcher · Router · Manager       ProcessTerminationService
  Settings · About · SharedUI       PermissionService · ShellCommand
            |                       UtilityCatalog · UtilitySelection
            |
   Utilities/<Name>  ──uses──▶  Sources/<Name>Kit (models · parsers · services)
```

## Principles
- **Shell vs utilities.** The shell knows only utility *metadata* (`UtilityInfo`) and a `UtilityModule` interface
  (summary, `didAppear`, `didDisappear`, `makeView`). It never knows how a utility gathers data.
- **UI-free logic.** Everything testable lives in `MacPeekCore` and `<Name>Kit` and builds on Linux CI. SwiftUI/AppKit
  code is `#if os(macOS)` and thin.
- **Discovery behind protocols.** Utilities depend on a protocol (e.g. `PortDiscoveryProtocol`), never on shell output.
  `LsofPortDiscovery` can be replaced by a native implementation without touching the UI.
- **No work when not visible.** Modules start refreshing in `didAppear()` and stop in `didDisappear()`. The router calls
  `didDisappear()` when the user leaves the screen, disables the utility, or the popover closes. The launcher takes one
  cheap, one-shot summary per enabled utility when the popover opens.
- **Disabled = zero work.** A utility switched off in *Manage utilities* is not summarized, shown or started. The
  *disabled* set is persisted (not the enabled set), so utilities shipped later appear enabled by default.

## Navigation
`UtilityRouter` owns a `Route` (`launcher`, `utility(id)`, `manage`, `settings`, `about`) inside the single compact
popover. Every sub-screen has a back button; the popover always reopens on the launcher.

## Safe termination
`ProcessTerminationService` (MacPeekCore) is the only code that signals processes. A utility supplies a
`TerminationResource` describing what the user acted on (PortPeek: one socket = PID + address + port + protocol):

1. `check(pid:)` re-queries the resource: still owned by this PID? gone? changed? unavailable?
2. Process name and **start time** must match what the user saw (PID-reuse guard). A missing timestamp is a refusal.
3. SIGTERM, wait, verify exit, then `releaseState(pid:)`: released, taken over by another process, or still held.
4. SIGKILL only via an explicit second call, which revalidates again.
5. PID 1 and MacPeek itself are never signalled.

## Evaluating a new utility
1. Does macOS already expose the information? 2. Is it hard to reach? 3. Is the problem frequent?
4. One-sentence explanation? 5. Runs locally? 6. Stays lightweight? 7. Needs dangerous permissions?
8. Duplicates an existing excellent utility? Build only if it passes strongly.

## Non-goals
Not Activity Monitor, iStat Menus, a cleaner, RAM booster, antivirus, optimizer, cloud/remote admin tool, AI assistant,
or a cross-platform app.
