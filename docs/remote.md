# Remote management protocol

MacPeek can be managed from MacPeek Remote, a separate console app that needs a MacPeek Remote account. This page
describes what the agent built into MacPeek does, so it can be reviewed. The code is in `Sources/RemoteCrypto`,
`Sources/RemoteProtocol` and `Sources/RemoteAgent`.

## Rules
1. **Off by default.** While Remote management is off, MacPeek creates no identity, opens no socket and advertises
   nothing. Turning it off ends every connection at once.
2. **Only your account.** A Mac is reachable only after its person adds it to their MacPeek Remote account
   ([Adding a Mac](#adding-a-mac)), and then only by devices of that account.
3. **Separate switches.** Reading is allowed to the account's devices. Actions need the Mac's **Allow actions** switch,
   off until turned on, *and* a role that may act. **Allow from anywhere** ([Relay](#relay)) is turned on when the Mac
   joins an account, which the Mac says; it can be turned off at any time and does not turn on actions.
4. **Visible.** The menu-bar icon carries a dot and its tooltip says so while Remote management is on.
5. **No new privileges.** The agent runs inside MacPeek as the person's user. Actions use the same
   `ProcessTerminationService` checks as the app (same process, still holding the port, SIGTERM first, force only when
   asked).
6. **Recorded.** Joining or leaving an account, access changes, revocations and every action (allowed or refused) go to
   a hash-chained activity log shown in Settings.

## Discovery and transport
The Mac listens on a TCP port chosen by the system and advertises `_macpeek._tcp` with its computer name; with **Allow
from anywhere** on it also keeps a connection to the relay. Frames are a 4-byte big-endian length and a JSON
`WireMessage`; frames over 8 MiB end the connection. The transport adds no security of its own: everything below
protects itself.

## Identities
Each side has a long-term Ed25519 key. The Mac's private key is in the login Keychain
(`kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`). Names are for display only; trust is always by key. Fingerprint:
the first 8 bytes of SHA-256 of the public key, shown in four groups.

## Adding a Mac

**Add to my account…** in Settings ▸ Remote management is the only way to add a Mac, on the same network or not. The
code is `Sources/RemoteCrypto/AccountJoin.swift` and `Sources/RemoteAgent/AccountJoinFlow.swift`; the service side is
MacPeek Remote's `cloud/src/joins.ts`.

1. The Mac asks the service (`POST /mac-joins`), signing `macpeek-join-request-v1`, its key, its name and the time
   (lines joined with `\n`) with its identity key. It gets an id, a secret only it holds and a page on the account
   site, which it opens in the browser.
2. The person signs in there and chooses **Add**: the request goes to their account.
3. MacPeek Remote, signed in to that account on their main Mac, asks to approve it. Approving sends the account's
   *grant*: the workspace id, its Ed25519 workspace public key, a display name and the console's certificate chain.
4. The Mac checks that the grant is consistent (the chain verifies against the key it names), signs its *claim* and
   sends it; once the service has it, the Mac stores `{workspace id, workspace key, access}` in
   `~/Library/Application Support/MacPeek/Remote/workspace.json` (mode 0600). The access is **View and act**; actions
   still need **Allow actions**. It turns on **Allow from anywhere**, and Settings and a notification say so. If the
   claim cannot be sent, nothing changes on the Mac and the person can start again.

A request lasts 30 minutes, and Remote management must be on. A Mac belongs to one account at a time; adding it to
another one replaces it and ends the old account's sessions.

**What this trusts.** Adding a Mac relies on MacPeek Remote's service to hand the Mac the grant the console sent: whoever
controlled the service while a Mac joins could give that Mac a workspace key of its own. Once joined, the Mac keeps the
key it pinned, and everything after that is end-to-end encrypted and checked against it, whatever the service does.

**Which service.** Production (`api.macpeekapp.com`) by default. A build made with
`MACPEEK_ENV=staging scripts/build-app.sh` uses staging (`api.staging.macpeekapp.com`), as MacPeek Remote's script does;
`MACPEEK_API_URL` in the environment, or `defaults write app.macpeek.MacPeek remote.serviceURL <url>`, overrides either.
The Mac, the console and the account site must all use the same service, or the request is never found.

## Sessions
Every connection runs a SIGMA-I handshake with fresh X25519 keys:

```text
console → Mac   Hello    consoleEphemeral
Mac → console   Reply    macEphemeral, sealed { Mac identity, signature over "macpeek-session-identity-v1 mac" ‖ transcript }
console → Mac   Finish   sealed { console identity and its certificate chain, signature over "… console" ‖ transcript }
```

`transcript = SHA-256("macpeek-session-v1" ‖ consoleEphemeral ‖ macEphemeral)`; keys come from HKDF over the shared
secret with that salt. A Mac in no account refuses the Hello. The Mac accepts the Finish only when the chain verifies
against the pinned workspace key for the very key that signed it and no key in it is on the revocation list; the console
accepts only the Mac key it knows from the account. Fresh keys give forward secrecy. After the handshake every frame is
`sealed(ChaCha20-Poly1305)` with a per-direction key and a nonce of 4 zero bytes and a 64-bit counter, so a changed,
replayed, dropped or reordered frame fails to open and ends the connection.

## Certificates
Every signed message is UTF-8 text, fields joined by `\n` (no field may contain a newline), keys in standard base64,
times in milliseconds:

```text
member  = Sign_issuer("macpeek-member-v1" \n workspace id \n member id \n member key \n role \n issued)
device  = Sign_member("macpeek-device-v1" \n workspace id \n member id \n device id \n device key \n name \n issued)
revoked = Sign_workspace("macpeek-revocations-v1" \n workspace id \n sequence \n sorted keys joined by ",")
claim   = Sign_Mac("macpeek-claim-v1" \n Mac key \n workspace id \n time)
```

A chain is one member certificate signed by the workspace key, or two when a team admin (`owner` or `admin` role)
certified the member with their own key; an admin cannot certify an owner, and nothing longer is accepted. Roles are
`owner`, `admin`, `operator` and `viewer`; a viewer only reads, anyone else gets the access chosen on the Mac.

## Requests
Inside a sealed frame is an `Envelope` (`version`, `id`, `kind`, `operation`, JSON `payload`). Reads return the Kits'
own models: `agent.capabilities`, `device.info`, `cpu.topology`, `cpu.snapshot`, `memory.stats`, `process.usage`,
`disk.volumes`, `network.counters`, `network.snapshot`, `ports.list`, `processes.list`, `sleep.snapshot`,
`dns.configuration` and `dns.probe` (only to a server in the Mac's own DNS configuration, for a valid host name),
`network.extras` (proxy, VPN, Tailscale, remembered Wi-Fi networks), `dns.overrides` (`/etc/hosts`, `/etc/resolver`),
`bluetooth.devices` (devices and battery levels, never addresses), `processes.origin` and `processes.openFiles` (both carry the
process the console saw and are answered only while that PID still belongs to it, same start time), `containers.snapshot`,
`gpu.snapshot` and `models.snapshot`. Container logs are not offered remotely. Actions are `ports.free`, `processes.quit` and
`containers.action` (start, stop, restart, pause, resume or remove one container; the container ID must be 12–64 hex
characters and the Mac re-lists it and refuses if it is gone, renamed or in the wrong state); they carry the row the console
saw, which the Mac re-validates before acting, and need a role that may act with "Allow actions" on.
Readings that need two samples (GPU time, power, container-VM and runner CPU) are kept by the agent between requests, so a
rate covers the interval since the previous request from any console. A console checks `agent.capabilities` before using
an operation, so older Macs simply do not show the newer Peeks.
The device's chain is checked again for every request, so a revocation, leaving the account or a changed access level
applies at once.
Errors: `unsupportedVersion`, `unknownOperation`, `invalidPayload`, `notPermitted`, `actionsDisabled`, `unavailable`.

**Account operations.** None is an action, so "Allow actions" does not gate them:

| Operation | Body | What it does |
|---|---|---|
| `workspace.status` | — | Returns the workspace id, the revocation list number and a fresh claim |
| `workspace.revocations` | a revocation list | Stored when signed by the pinned workspace key with a higher number than the one held; open sessions of newly revoked devices end at once. Any console of the account may deliver it |

**On the Mac**, Settings ▸ Remote management shows the account, the access its devices get, the devices that connected
and **Remove from account**. Every change is in the activity log.

## Activity log
`~/Library/Application Support/MacPeek/Remote/activity-log.json` (mode 0600), newest 500 entries. Each entry stores the
SHA-256 of its fields and the previous entry's hash, so an edited, removed or reordered entry is shown as tampered. It
detects changes; it cannot stop someone with access to the account from deleting the file.

## Relay

**Allow from anywhere** lets the devices of this Mac's account reach it from any network, without opening a port. It is
turned on when the Mac joins an account, can be turned off in Settings ▸ Remote management, and needs Remote
management on. The relay accepts only Macs whose claim the service holds, and only consoles that are active devices of
that account, with a trial or subscription in force. The code is `Sources/RemoteAgent/RelayClient.swift` and
`Sources/RemoteCrypto/Relay.swift`; the relay itself is in MacPeek Remote's `cloud/src/relay.ts`.

- **Connection.** While the switch is on, the Mac keeps one outbound WebSocket (TLS) to
  `wss://relay.macpeekapp.com/relay/mac/<mac id>`, where the Mac id is the hex SHA-256 of its public key. The relay
  sends a fresh 32-byte challenge; the Mac signs `macpeek-relay-mac-v1`, its id and the challenge (lines joined with
  `\n`) with its identity key. No account, token or password is stored on the Mac. A ping every 30 seconds keeps the
  connection open; after a drop the Mac reconnects after 2 seconds, doubling to at most 5 minutes. A Mac the relay does
  not know as part of an account asks again every 15 minutes.
- **Streams.** Each console that connects through the relay becomes a numbered stream on that socket and gets its own
  connection in the agent, exactly like a TCP connection on the local network: the same frames, the same handshake
  against the pinned workspace key, the same check of every request, the same **Allow actions** switch.
- **What the relay sees.** Which Mac and which device connect, IP addresses, times and byte counts. It keeps whether
  the Mac is connected and when it last was, nothing else.
- **Off.** Turning the switch off, turning Remote management off or leaving the account closes the relay connection
  and every console stream on it at once. Removing the Mac from the account on the service side closes it too.
- **Logged.** Turning the switch on or off is recorded in the activity log.

## Not covered
- A person who controls this Mac's user account (they can read the Keychain item and the files).
- Whoever controls MacPeek Remote's service while a Mac is being added ([Adding a Mac](#adding-a-mac)).
- The workspace private key lives in the account owner's encrypted vault, so each of the owner's devices that can open
  the vault holds it. Revoking a stolen owner device stops that device, but someone who also got its vault open could
  certify a new device; until replacing the workspace key in place is built (with teams), the remedy is **Remove from
  account** on each Mac and adding it again. A revocation reaches a Mac when a console of the account connects to it.
- Denial of service: a peer on the local network can open and hold connections; the relay can drop or delay traffic.
  Neither can read or change anything, or connect a device the Mac does not trust.

## Planned: history

Not implemented; recorded here so the changes can be reviewed before they are built.

- **History.** While Remote management is on, the Mac keeps 30 days of 30-second CPU, memory, disk and network points
  (about 2.6 MB) on the Mac, and a new `history.range` request returns them to the account's devices as compact binary
  chunks. Nothing is sent anywhere unless one of them asks for it.
