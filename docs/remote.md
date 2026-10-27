# Remote management protocol (version 1)

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
- The relay and accounts, which are not implemented.
