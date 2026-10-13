# Security Policy

## Supported versions
Only the latest released version receives security fixes.

## Reporting a vulnerability
Please **do not open a public issue**. Use GitHub's private
[security advisory form](../../security/advisories/new) for this repository. Include the MacPeek
version, macOS version and reproduction steps. We aim to acknowledge reports within 7 days and to
credit reporters who want it once a fix ships (responsible disclosure).

## Security model
- **No telemetry, no accounts, no cloud.** Nothing is sent to MacPeek or any analytics service. The only network
  traffic is what you ask for, each only when you press the button: NetPeek pings your router and DNS servers,
  DNSPeek looks up a name you type, UpdatePeek's **Check now** asks Apple's update servers (`softwareupdate --list`),
  and UpdatePeek's npm check and npm **Update** use the npm registry, which sees the names of your global packages
  (and serves the package you update), as it does whenever you run npm yourself.
- **No privilege elevation.** MacPeek runs as your user and sends signals only to processes your
  user may signal. It never prompts for, stores or requests administrator rights. When npm is refused permission to
  update a global package, UpdatePeek only **shows** a `sudo npm install -g <name>@latest` command to copy into
  Terminal; it never runs `sudo`, and the password is typed in Terminal, never into MacPeek.
- **Installs only on explicit confirmation.** UpdatePeek never installs macOS or Homebrew updates. It runs
  `npm install -g <name>@latest` only for one package you pressed **Update** on and confirmed, with a strictly validated
  package name (so it cannot become an option or a second argument). Installing runs the package's own install scripts,
  as it would in Terminal.
- **Safe termination.** Before any signal the target is re-scanned and its port ownership, process
  name and start time are re-verified (guards against PID reuse); a missing start time is a refusal. SIGTERM is always first; SIGKILL
  only after an explicit user action and a second revalidation. PID 1 and MacPeek itself are refused. All
  utilities share one termination service (`ProcessTerminationService`).
- **No shell.** System tools are executed directly with separate arguments; no untrusted string is ever concatenated
  into a command line.
- **No secrets in the repository.** Signing certificates and notarization keys live only in GitHub
  Actions secrets (see `.github/workflows/release.yml`).
- **Distribution.** Releases are Developer ID signed, hardened-runtime, Apple-notarized and stapled;
  each DMG ships with a SHA-256 checksum.
