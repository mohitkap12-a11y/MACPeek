# NetPeek

**Question:** Is my network connection actually healthy?

## What it shows
- **The connection**: the interface the default route uses (and its Hardware Port name, "Wi-Fi", "Ethernet"…), its IPv4 and IPv6
  addresses, the router (gateway) and the DNS servers.
- **Wi-Fi** (when the active interface is Wi-Fi): signal and noise in dBm, signal-to-noise, channel and band, standard
  (802.11ac…), link rate and security.
- **Connection checks**, only when you press **Run checks**: three pings to the router and to each DNS server (up to three,
  IPv4 only), run side by side.
- Other connections (VPNs, bridges) collapsed.

| Field | Source |
|---|---|
| Interface, router | `route -n get default` (exit status 1 = no default route, which is reported as "not connected", not an error) |
| Addresses, reachability | `scutil --nwi` |
| Hardware Port names | `networksetup -listallhardwareports` |
| DNS servers | `scutil --dns` (shared with DNSPeek) |
| Wi-Fi details | `system_profiler SPAirPortDataType -json` (slower, loaded once per visit) |
| Checks | `ping -c 3 -t 5 <ipv4>` |

## Fact versus inference
Each statement under Connection checks is labelled **Measured or reported** (a ping result, a signal reading) or
**Likely (inference)** (for example "lost packets to the router often mean a weak signal"). The signal band
(Excellent/Good/Fair/Weak) is a common rule of thumb, not something macOS reports. **No reply to a ping is never presented as
proof of an outage**: some devices ignore ICMP.

## Wi-Fi network name
macOS replaces the network name with `<redacted>` for apps without Location access (a real capture shows exactly that).
MacPeek does not request Location access, so NetPeek shows "Hidden by macOS" rather than a name.

## Refresh and privacy
The cheap connection snapshot refreshes while the screen is open (at least every 5 s); nothing runs when it is not. Wi-Fi
details load once per visit. Pings go **only** to your router and DNS servers (never a third-party host), only when you press the
button, and the results are discarded when you leave the screen. Everything handed to `ping` is validated as an IPv4 literal first.

## Limits
- Link rate is what the radio negotiated, not your internet speed. NetPeek runs no speed tests.
- Only IPv4 targets are pinged; IPv6 DNS servers are listed as skipped.
- On a Mac with several active connections, "primary" means the one the default route uses.

## Verified against
A Mac mini (Mac14,3) on Wi-Fi. Fixtures: `Tests/NetPeekKitTests/Fixtures/` (route, nwi, hardware ports, ping, Wi-Fi profiler, with
the IPv6 address replaced). Ethernet, VPN and offline captures were not available; offline is covered by a synthetic `scutil --nwi`.
