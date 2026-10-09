# PrivacyPeek

**Question:** What does this macOS privacy permission mean?
**Informational only.** Non-goals: showing which apps hold a permission, granting/revoking/resetting any permission
(including MacPeek's own), malware or risk verdicts.

## What it shows
A built-in guide to Camera, Microphone, Screen (& System Audio) Recording, Accessibility, Input Monitoring, Full Disk Access,
Files & Folders, Location Services, Contacts, Calendars, Photos, Bluetooth and (macOS 15+) Local Network: what each generally
allows, notes (menu-bar indicators, renames), **Learn** and **Open Settings**. The UI states that macOS controls every
authorization and that granted/absent does not imply unsafe/safe.

## Settings routes
`x-apple.systempreferences:com.apple.preference.security?Privacy_<Anchor>` → Privacy & Security → System Settings root.
Each pane lists its fallbacks in order; the opener tries them until macOS accepts one, and shows an error banner if none does.
These deep links are an Apple convention, not a documented API. They are tested here for shape and fallback order, but
**must be checked by hand on each supported macOS version** before release (see the capability report).

## Version differences
"Screen Recording" is named "Screen & System Audio Recording" from macOS 15; Local Network is listed from 15. Both are
encoded from observed behaviour and should be re-verified.

## Permissions and privacy
None. Reads nothing from the Mac, requests nothing, touches no TCC data, logs nothing, makes no network request.

## Testing
`swift test --filter PrivacyPeekKitTests`. Manual: every Open Settings button on each supported macOS version, including
that a failing deep link lands on Privacy & Security; confirm no permission prompt ever appears.
