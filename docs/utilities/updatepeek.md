# UpdatePeek

**Question:** What updates can MacPeek verify?
**Non-goals:** installing, downloading or scheduling updates; replacing Software Update or vendor updaters.

## What it shows
- **macOS version and build** (`ProcessInfo` + `sysctl kern.osversion`), and **Open Software Update**.
- **macOS update status is not checked** and is labelled that way. `softwareupdate --list` output is not a stable API and
  could not be validated on every supported macOS version, so UpdatePeek does not guess or say "up to date".
- **Homebrew** (only if installed at `/opt/homebrew/bin/brew` or `/usr/local/bin/brew`): press **Check** to run
  `brew outdated --json=v2`. Shown per package: kind, installed → current version, with the source and check time.
  "Homebrew reports no outdated packages" is shown as exactly that, not as "up to date".
- **Other apps:** "update status unavailable — no supported update source". Not inferred from bundle metadata or web pages.

## How Homebrew is run
Fixed executable `/usr/bin/env`, fixed argument array
`HOMEBREW_NO_AUTO_UPDATE=1 HOMEBREW_NO_ANALYTICS=1 HOMEBREW_NO_ENV_HINTS=1 <brew> outdated --json=v2`. No shell, no
interpolation, 60 s limit, cancelled when you leave the screen. MacPeek never runs `brew update`, so the answer reflects
Homebrew's last-fetched index, and the UI says so. Output is JSON-parsed strictly; anything else is "could not be
understood" (retryable). Raw command output and error text are never shown.

## Update actions
- macOS: opens Software Update. Nothing is installed.
- Homebrew: **Copy command** (`brew upgrade <name>` / `brew upgrade --cask <name>`) for you to run in Terminal. Offered only
  for a package Homebrew just listed, with a validated name (no leading `-`, restricted character set). MacPeek does not run
  `brew upgrade`: cask upgrades can ask for a password and the no-elevation route is not verified.

## Permissions and privacy
None added. MacPeek makes no network request itself.

## Minimum macOS
13.

## Testing
`swift test --filter UpdatePeekKitTests` (JSON parsing incl. malformed/chatty output, fixed argv, missing Homebrew, failure
mapping, action gating and malicious names). Manual: Homebrew absent; present with and without outdated packages; Homebrew
broken (e.g. rename `brew`); older and newest macOS. Do not install anything during tests.
