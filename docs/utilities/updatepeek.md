# UpdatePeek

**Question:** What updates are available?
**Non-goals:** installing macOS or Homebrew updates, scheduling updates, replacing Software Update or vendor updaters.

## What it shows
- **macOS version and build** (`ProcessInfo` + `sysctl kern.osversion`).
- **macOS update status**, with two sources, always labelled:
  - macOS's own record of its last background check (`RecommendedUpdates` in `/Library/Preferences/com.apple.SoftwareUpdate.plist`,
    world-readable). Read locally on open; no command, no request. If macOS has found an update, it is listed here and the
    launcher shows "N updates found". This can be stale, and an empty record proves nothing, so with no record the status is
    **Not checked**.
  - **Check now** runs `softwareupdate --list`, which asks Apple's update servers. The result is either the list of updates
    (name, version, Recommended, Restart required) or "macOS reports no new software available", with the time of the check.
    Anything the output parser does not recognise is a failure ("could not be understood"), never "nothing to do".
- **Open Software Update** (prominent button): opens System Settings → General → Software Update, where updates are
  installed. MacPeek never installs macOS updates.
- **Homebrew** (only if installed at `/opt/homebrew/bin/brew` or `/usr/local/bin/brew`): press **Check** to run
  `brew outdated --json=v2`. Shown per package: kind, installed → current version, with the source and check time.
  "Homebrew reports no outdated packages" is shown as exactly that.
- **npm** (only if found at `/opt/homebrew/bin/npm` or `/usr/local/bin/npm`): press **Check** to run
  `npm outdated --global --json`. Shown per **globally installed** package: installed → latest version, with the source and
  check time. Project dependencies are not checked. npm installed through nvm, fnm or Volta lives elsewhere and is not
  detected (stated in the UI).
- **Other apps:** "update status unavailable". Not inferred from bundle metadata or web pages.

## How macOS is checked
Fixed executable `/usr/sbin/softwareupdate`, fixed argument `--list`, no shell, 120 s limit, cancelled when you leave the screen.
The tool writes progress to stderr and the list to stdout, so both are read. Exit status other than 0 is a failure with a
fixed message. **This contacts Apple's update servers**, so it is a network request, made only when you press Check now. It only
lists: nothing is downloaded or installed. The `softwareupdate --list` format is stable but not a documented API; it was
written from the known format and **has not been verified on every supported macOS version** (see the checklist in
[the capability report](../next-peeks-capability-report.md)). The local record's key names are likewise unverified on hardware;
if a key is absent the status simply stays "Not checked".

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
- npm: **Update** and **Copy command** (`npm install -g <name>@latest`).
  - **Update** asks you to confirm the exact command, then runs it: `/usr/bin/env PATH=… <npm> install --global --no-audit
    --no-fund <name>@latest`, 300 s limit, one package at a time. It is offered only for a package npm just listed, with a
    strictly validated npm name (lowercase letters, digits and `- . _ ~`, optionally `@scope/name`, never starting with `.`,
    `_` or `-`), so a name can never become an option or a second argument. Installing runs the package's own install scripts,
    exactly as it would in Terminal, and downloads from the registry.
  - It **never elevates**. If npm cannot write to its global folder (common with the nodejs.org installer, which installs
    under `/usr/local`), the install fails with a fixed explanation and you can run the copied command yourself.
    npm's own error text is never shown.
  - An update that has started is **not cancelled** when you leave the screen, so an install is never interrupted halfway;
    the result shows when you return. After a successful update npm is asked again (if the screen is open), so the list
    shows what is really left.

## Permissions and privacy
No permission needed. MacPeek makes no network request of its own, but **three actions use the network**, each only when you press
its button: **Check now** (Apple's update servers), the **npm Check** (the npm registry, which sees the names of your global
packages) and an npm **Update** (the registry serves the package). Homebrew's check makes no request (auto-update is switched
off). Nothing runs when you open the screen except reading the local Software Update record.

## Minimum macOS
13.

## Testing
`swift test --filter UpdatePeekKitTests` (Homebrew and npm JSON parsing incl. malformed/chatty output, npm's exit codes and
`error` object, `softwareupdate --list` parsing incl. "no new software", titles with commas, unrecognised output, the local
record incl. wrong types and oversized files, fixed argv for every command, missing tools, failure mapping, install gating and
malicious names). Manual: Homebrew and npm absent; present with and without outdated packages; broken (e.g. rename `brew`);
offline for npm and Check now; npm from nvm (expect "not found"); an npm global folder you cannot write to (expect the
permission explanation, not a prompt); a Mac with a pending macOS update (compare with Software Update) and one without;
older and newest macOS. Do not install anything except a throwaway npm package during tests.
