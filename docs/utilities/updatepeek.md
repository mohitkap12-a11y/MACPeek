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
- **npm** (only if found at `/opt/homebrew/bin/npm` or `/usr/local/bin/npm`): press **Check** to run
  `npm outdated --global --json`. Shown per **globally installed** package: installed → latest version, with the source and
  check time. Project dependencies are not checked. npm installed through nvm, fnm or Volta lives elsewhere and is not
  detected (stated in the UI). "npm reports no outdated global packages" is shown as exactly that.
- **Other apps:** "update status unavailable — no supported update source". Not inferred from bundle metadata or web pages.

## How Homebrew is run
Fixed executable `/usr/bin/env`, fixed argument array
`HOMEBREW_NO_AUTO_UPDATE=1 HOMEBREW_NO_ANALYTICS=1 HOMEBREW_NO_ENV_HINTS=1 <brew> outdated --json=v2`. No shell, no
interpolation, 60 s limit, cancelled when you leave the screen. MacPeek never runs `brew update`, so the answer reflects
Homebrew's last-fetched index, and the UI says so. Output is JSON-parsed strictly; anything else is "could not be
understood" (retryable). Raw command output and error text are never shown.

## How npm is run
Fixed executable `/usr/bin/env`, fixed argument array
`PATH=<npm's directory>:/usr/bin:/bin:/usr/sbin:/sbin npm_config_update_notifier=false npm_config_fund=false <npm> outdated --global --json`.
npm is a script that needs `node`, and a menu-bar app has a minimal `PATH`, so npm's own directory (where Homebrew and the
nodejs.org installer also put `node`) goes first. No shell, no interpolation, 90 s limit, cancelled when you leave the screen.
**Unlike Homebrew, npm contacts the registry** (npmjs.org unless your npm config says otherwise), so this check is a network
request, made only when you press Check. npm exits 1 when it finds outdated packages, so exit 0 and 1 are both read; with
`--json`, npm reports its own failures (for example no network) as an `error` object, which is shown as a failure and never
as a package. Output is JSON-parsed strictly; anything else is "could not be understood" (retryable). Raw command output and
error text are never shown. "Latest" can be a new major version, and the UI says to read the package's notes first.

## Update actions
- macOS: opens Software Update. Nothing is installed.
- Homebrew: **Copy command** (`brew upgrade <name>` / `brew upgrade --cask <name>`) for you to run in Terminal. Offered only
  for a package Homebrew just listed, with a validated name (no leading `-`, restricted character set). MacPeek does not run
  `brew upgrade`: cask upgrades can ask for a password and the no-elevation route is not verified.
- npm: **Copy command** (`npm install -g <name>@latest`). Offered only for a package npm just listed, with a validated npm
  name (lowercase letters, digits and `- . _ ~`, optionally `@scope/name`, never starting with `.`, `_` or `-`). MacPeek does
  not run `npm install`: a global install can need elevated rights depending on how Node was installed.

## Permissions and privacy
No permission needed. MacPeek makes no network request itself, but **the npm check does**: npm asks its registry, and the
registry sees what any `npm outdated -g` shows it (the names of your global packages). Nothing runs until you press Check.
Homebrew's check makes no request (auto-update is switched off).

## Minimum macOS
13.

## Testing
`swift test --filter UpdatePeekKitTests` (JSON parsing incl. malformed/chatty output, fixed argv, missing Homebrew or npm,
npm's exit codes and `error` object, failure mapping, action gating and malicious names). Manual: Homebrew and npm absent;
present with and without outdated packages; broken (e.g. rename `brew`); offline for npm; npm from nvm (expect "not found");
older and newest macOS. Do not install anything during tests.
