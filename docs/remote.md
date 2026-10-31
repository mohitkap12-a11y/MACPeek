# Remote management protocol (versions 1 and 2)

MacPeek can be managed from MacPeek Remote, a separate console app. This page describes what the agent built into MacPeek
does, so it can be reviewed. The code is in `Sources/RemoteCrypto`, `Sources/RemoteProtocol` and `Sources/RemoteAgent`.

## Rules
1. **Off by default.** While Remote management is off, MacPeek creates no identity, opens no socket and advertises
   nothing. Turning it off ends every connection at once.
2. **Separate switches.** Reading is allowed to paired consoles. Actions need the Mac's **Allow actions** switch *and* a
   console paired as "View and act". Relay access from outside the local network is not implemented.
3. **Visible.** The menu-bar icon carries a dot and its tooltip says so while Remote management is on.
4. **No new privileges.** The agent runs inside MacPeek as the person's user. Actions use the same
   `ProcessTerminationService` checks as the app (same process, still holding the port, SIGTERM first, force only when
   asked).
5. **Recorded.** Pairings, revocations, role changes, refused pairing attempts and every action (allowed or refused) go to
   a hash-chained activity log shown in Settings.

## Discovery and transport
The Mac listens on a TCP port chosen by the system and advertises `_macpeek._tcp` with its computer name. Frames are a
4-byte big-endian length and a JSON `WireMessage`; frames over 8 MiB end the connection. The transport adds no security
of its own: everything below protects itself.

## Identities
Each side has a long-term Ed25519 key. The Mac's private key is in the login Keychain
(`kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`). Paired consoles are stored by public key in
`~/Library/Application Support/MacPeek/Remote/paired-consoles.json` (mode 0600). Names are for display only; trust is
always by key. Fingerprint: the first 8 bytes of SHA-256 of the public key, shown in four groups.

## Pairing
The person at the Mac presses **Show pairing code**: a random 6-digit code, valid 5 minutes, at most 3 wrong attempts,
usable for one pairing.

```text
console → Mac   Start    commitment = SHA-256("macpeek-pair-commit-v1" ‖ consoleEphemeral ‖ consoleNonce)
Mac → console   Accept   macEphemeral (X25519), macNonce (32 bytes)
console → Mac   Reveal   consoleEphemeral, consoleNonce, codeProof
```

Both sides compute `shared = X25519(…)` and `transcript = SHA-256("macpeek-pair-v1" ‖ commitment ‖ macEphemeral ‖
macNonce ‖ consoleEphemeral ‖ consoleNonce)`. `codeProof = HMAC-SHA256(HKDF(shared, salt: transcript, info: "code " ‖
code), transcript)`. The Mac checks the commitment and the proof. Committing first stops a person in the middle from
choosing their key after seeing the Mac's.

Both screens then show four words derived from `HKDF(shared, salt: transcript, info: "matching words")` (32 bits). A
person in the middle has two different shared secrets, so the words differ. **Each side sends Confirm only after its own
person has checked the words**:

```text
Confirm = ChaCha20-Poly1305(key: HKDF(…, "console to mac" | "mac to console"),
                            { identity, Ed25519 signature over "macpeek-identity-v1 <role>" ‖ transcript })
```

The Mac must wait for its person as well, because the code proof can be brute-forced offline by someone who intercepted
it (10⁶ codes); the words are what defeats that. A pairing is stored only when the console's Confirm verifies and the
person at the Mac chose **They match** and a role.

## Sessions
Every later connection runs a SIGMA-I handshake with fresh X25519 keys:

```text
console → Mac   Hello    consoleEphemeral
Mac → console   Reply    macEphemeral, sealed { Mac identity, signature over "macpeek-session-identity-v1 mac" ‖ transcript }
console → Mac   Finish   sealed { console identity, signature over "… console" ‖ transcript }
```

`transcript = SHA-256("macpeek-session-v1" ‖ consoleEphemeral ‖ macEphemeral)`; keys come from HKDF over the shared
secret with that salt. Each side accepts only a pinned key. Fresh keys give forward secrecy. After the handshake every
frame is `sealed(ChaCha20-Poly1305)` with a per-direction key and a nonce of 4 zero bytes and a 64-bit counter, so a
changed, replayed, dropped or reordered frame fails to open and ends the connection.

## Requests
Inside a sealed frame is an `Envelope` (`version`, `id`, `kind`, `operation`, JSON `payload`). Reads return the Kits'
own models: `agent.capabilities`, `device.info`, `cpu.topology`, `cpu.snapshot`, `memory.stats`, `process.usage`,
`disk.volumes`, `network.counters`, `network.snapshot`, `ports.list`, `processes.list`, `sleep.snapshot`,
`dns.configuration` and `dns.probe` (only to a server in the Mac's own DNS configuration, for a valid host name). Actions are
`ports.free` and `processes.quit`; they carry the row the console saw, which the Mac re-validates before signalling.
The console's pairing and role are looked up again for every request, so revoking or changing a role applies at once.
Errors: `unsupportedVersion`, `unknownOperation`, `invalidPayload`, `notPermitted`, `actionsDisabled`, `unavailable`.

## Activity log
`~/Library/Application Support/MacPeek/Remote/activity-log.json` (mode 0600), newest 500 entries. Each entry stores the
SHA-256 of its fields and the previous entry's hash, so an edited, removed or reordered entry is shown as tampered. It
detects changes; it cannot stop someone with access to the account from deleting the file.

## Not covered
- A person who controls this Mac's user account (they can read the Keychain item and the files).
- Denial of service on the local network: a peer can open and hold connections, and can occupy the one pairing slot
  while a code is on screen (the person can cancel and show a new code). A peer that is not paired gets nothing else.
- The relay, which is not implemented (see below).

## Accounts (protocol version 2)

MacPeek itself stays free and never asks for an account: accounts belong to the person using MacPeek Remote. Version 2
only adds to version 1, so either app can be older: the envelope stays at version 1, unknown JSON fields are ignored,
and an agent that speaks version 2 reports `protocolVersion: 2` and the `workspace.*` operations in
`agent.capabilities`. The code is `Sources/RemoteCrypto/Workspace.swift`.

**What the Mac pins.** A console signed in to an account adds a *grant* to its pairing Confirm: the account's workspace
id, its Ed25519 workspace public key, a display name and the console's certificate chain. The code-and-four-words
ceremony is unchanged, and the Mac shows "This adds this Mac to …'s MacPeek account" next to the words. When the person
at the Mac confirms, it stores `{workspace id, workspace key, the access they chose}` in
`~/Library/Application Support/MacPeek/Remote/workspace.json` (mode 0600) instead of pinning that console, and returns a
*claim* in its own Confirm. A Mac belongs to one workspace at a time; pairing into another one at the Mac replaces it and
ends the old account's sessions.

**Certificates.** Every signed message is UTF-8 text, fields joined by `\n` (no field may contain a newline), keys in
standard base64, times in milliseconds:

```text
member  = Sign_issuer("macpeek-member-v1" \n workspace id \n member id \n member key \n role \n issued)
device  = Sign_member("macpeek-device-v1" \n workspace id \n member id \n device id \n device key \n name \n issued)
revoked = Sign_workspace("macpeek-revocations-v1" \n workspace id \n sequence \n sorted keys joined by ",")
claim   = Sign_Mac("macpeek-claim-v1" \n Mac key \n workspace id \n time)
```

A chain is one member certificate signed by the workspace key, or two when a team admin (`owner` or `admin` role)
certified the member with their own key; an admin cannot certify an owner, and nothing longer is accepted. Roles are
`owner`, `admin`, `member` and `viewer`; a viewer only reads, anyone else gets the access chosen on the Mac.

**Sessions.** The console's Finish carries its chain next to its identity, inside the same encrypted box. The Mac
accepts the handshake when the chain verifies against the pinned workspace key for the very key that signed the Finish
and no key in it is on the revocation list. Pinned version 1 consoles are accepted as before. The chain is checked again
on every request, so a revocation, leaving the account or a changed access level applies at once.

**Operations.** None is an action, so "Allow actions" does not gate them:

| Operation | Body | What it does |
|---|---|---|
| `workspace.status` | — | Returns the workspace id (or none), the revocation list number, a fresh claim and whether this console came in through the workspace |
| `workspace.adopt` | a grant | "Move this Mac to your account", from a console paired on its own: the Mac joins that workspace with the access the console had, forgets the console's own pairing, posts a notification and logs it. Refused when the Mac already belongs to another account (that needs pairing at the Mac). **Undo move** in Settings restores the console's pairing |
| `workspace.revocations` | a revocation list | Stored when signed by the pinned workspace key with a higher number than the one held; open sessions of newly revoked devices end at once. Any console of the account may deliver it |

**On the Mac**, Settings ▸ Remote management shows the account, the access its devices get, the devices that connected
through it, **Undo move** and **Remove from account**. Every change is in the activity log.

**Not covered yet.** The workspace private key lives in the account owner's encrypted vault, so each of the owner's
devices that can open the vault holds it. Revoking a stolen owner device stops that device, but someone who also got its
vault open could certify a new device; until replacing the workspace key in place is built (with teams), the remedy is
**Remove from account** on each Mac and pairing again. A revocation reaches a Mac only when a console of the account
connects to it on the local network; with the relay it will reach it at once.

## Planned: relay and history

Not implemented; recorded here so the changes can be reviewed before they are built.

- **Relay.** A separate "Allow from anywhere" switch, off by default. When on, the Mac keeps one outbound WebSocket to
  the relay and authenticates by signing a challenge with its own key; no account or token is stored on the Mac.
  Sessions through the relay are the same end-to-end SIGMA-I sessions as on the LAN, and actions still need **Allow
  actions**.
- **History.** While Remote management is on, the Mac keeps 30 days of 30-second CPU, memory, disk and network points
  (about 2.6 MB) on the Mac, and a new `history.range` request returns them to paired consoles as compact binary
  chunks. Nothing is sent anywhere unless a paired console asks for it.
