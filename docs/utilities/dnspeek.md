# DNSPeek

**Question:** Which DNS servers is my Mac using, and do they respond?

## What it shows
- **DNS servers in use**: the name servers of the resolver macOS uses for ordinary names (the first resolver with no domain of
  its own), in order, with the interface and reachability macOS reports.
- **Search domains**, **per-domain resolvers** (names under one domain go to specific servers, common with VPNs), and a note
  for **multicast DNS** zones (`.local` and the link-local reverse zones, answered on your network rather than by a server) and
  **scoped** resolvers (queries bound to one interface).
- **Run lookup**: resolves a name the way apps do, then asks each active server directly.

| Field | Source |
|---|---|
| Configuration | `scutil --dns` |
| System lookup | `dscacheutil -q host -a name <name>` (verified); the time is the wall-clock time of the whole run, including starting the tool, and may be a cache hit, so it is labelled "about" |
| Per-server query | `dig @<server> <name> A +time=2 +tries=1` |

## Verified versus not
`scutil --dns`, `dscacheutil` and `dig` (an answer and a timeout, DiG 9.10.6) parsing are all verified against real captures.
Anything the parsers do not recognise is shown as "unavailable", never guessed.

## Privacy and safety
Read-only: DNSPeek never changes DNS settings. Lookups run only when you press **Run lookup**, and only the name you typed is
queried (to your resolver and to each active server, up to four). The name must be a valid host name and the server an IP
address before anything is passed to a tool, so nothing typed can become an option or an extra argument. Results are discarded
when you leave the screen.

## Verified against
A Mac mini (Mac14,3) on Wi-Fi: `Tests/DNSPeekKitTests/Fixtures/` (`scutil --dns` with seven default resolvers, six of them mDNS, and
one scoped; `dscacheutil` with IPv4 and IPv6 answers). Per-domain resolvers and search domains are covered by a synthetic test.

## Local overrides: /etc/hosts and /etc/resolver
The usual answer to "why does this domain resolve to the wrong address?". DNSPeek reads both files directly (they are
world-readable) with the configuration and lists:
- **/etc/hosts** entries someone added (the localhost and broadcasthost entries macOS ships with are not counted), with
  their line numbers.
- **/etc/resolver/** files: the domain each one covers, its nameservers and port, and any other settings.
When the name in the lookup field is covered by either, DNSPeek says so next to the lookup ("/etc/hosts line 12 maps
api.example.com to 127.0.0.1"). It also notes that `dig` and `nslookup` ignore both files while apps do not. DNSPeek never
edits either file.
