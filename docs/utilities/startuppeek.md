# StartupPeek

**Question:** What starts automatically on this Mac?
**Non-goals:** a startup manager or cleaner. StartupPeek never disables, unloads, deletes, edits, moves or unregisters anything.

## What it shows
Grouped by kind, each row with its **type, scope, status and the source it was found in**:
- **MacPeek's own login item** (Service Management; status enabled / requires approval / not registered).
- **User launch agents** (`~/Library/LaunchAgents`), **system launch agents** (`/Library/LaunchAgents`) and
  **launch daemons** (`/Library/LaunchDaemons`): label, executable, status from the file (`RunAtLoad`/`KeepAlive` →
  "Starts automatically", timer/socket/watch triggers → "Starts on demand", `Disabled` → "Disabled in file").
- **Attribution**, always worded as inference: "Likely associated with *App*" (from an enclosing `.app` path or
  `AssociatedBundleIdentifiers`), and the **signing team ID** read from the code signature ("not validated").
- **Neutral observations** only: "Path is outside common application locations", "Attribution could not be verified",
  "The executable was not found at the listed path", "Another item uses the same label". Never "malware" or "suspicious".
- Actions: Reveal in Finder, Open Login Items Settings, Copy details.

## What it cannot see (stated in the UI)
Apps listed under System Settings → Login Items & Extensions (including "Allow in the Background") have no public API for
other apps to enumerate; `sfltool dumpbtm` needs administrator rights and the BackgroundTaskManagement database is
private, so neither is used. `/System/Library` is not listed. Whether a launchd job is currently loaded, and launchd's
override database for `Disabled`, are not read (that would need `launchctl`). **No list here is complete.**

## Safety
Property lists are untrusted: size-capped (1 MB), parsed with `PropertyListSerialization`, every value type-checked, never
executed. A malformed file still appears as "Status unknown". `SMAppService` is used only for MacPeek itself. No subprocess.

## Permissions and privacy
None added. Inaccessible folders are reported as a limitation, not worked around. Paths are shown in the UI (and copied
only when you press Copy) and are never logged. No network.

## Minimum macOS
13. Signature reading uses the Security framework (`SecStaticCode`), static inspection only.

## Testing
`swift test --filter StartupPeekKitTests` (temp-directory plists: parsing, wrong types, malformed, oversized, missing folder,
folder cap, duplicate labels, signature fakes, sorting, search, own-login-item mapping). Manual: a standard login item, a
background item, a user agent, a system agent/daemon, an app with no signature, an unreadable folder. Do not disable real services.
