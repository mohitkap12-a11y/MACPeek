# Development

## Prerequisites
- macOS 13+ (deployment target is declared in `Package.swift`)
- **Full Xcode 15+** — not just the Command Line Tools (see CONTRIBUTING → Troubleshooting the build)
- Node 22 for the website

## Commands
```bash
swift build                      # all targets
swift test                       # all tests (live lsof tests skip when lsof is unavailable)
swift test --filter MacPeekCoreTests
swift run MacPeek                # menu-bar app
open Package.swift               # Xcode
cd Website && npm ci && npm run check && npm run build && npm test
```

## Fixtures from a real Mac
Parsers for system tools (`system_profiler`, `pmset`, `ioreg`, `scutil`, …) must be built and verified against output
captured from a real Mac. Run `scripts/capture-fixtures.sh` — it saves masked, read-only command output to
`./macpeek-fixtures/` — then commit trimmed samples under `Tests/<Name>KitTests/Fixtures/`.

## Optional permissions
No utility requires administrator rights. Some details (other users' processes, Wi-Fi network name) are unavailable
without extra OS permissions; utilities show "Permission required" / "Information unavailable" instead of failing.

## Logging
Apple unified logging, subsystem `app.macpeek.MacPeek`, category `MacPeek.<Name>`. Never log secrets, clipboard
contents, environment values or device serials.
