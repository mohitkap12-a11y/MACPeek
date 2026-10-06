# PortPeek

**Question:** What is using port 3000?

## What it shows
Listening TCP and UDP sockets (IPv4 and IPv6, localhost and wildcard addresses) visible to your user account:
port, protocol, address, process name, PID, state and user. Search by port (partial too), process, PID, address
or protocol. Actions: inspect, copy port/PID/process/address, kill.

## How it works
`lsof -nP +c 0 -iTCP -sTCP:LISTEN -iUDP -FpcLftPnT` (fixed arguments, run directly, never through a shell) →
`PortParser` → `[PortInfo]`. The UI never touches `lsof`; it depends on `PortDiscoveryProtocol`.

## Refresh
One scan when the popover opens (for the launcher summary) and every 2 seconds (configurable 1–10 s) **only while the
PortPeek screen is open**. Manual refresh with ⌘R. A hung `lsof` is terminated after 10 s.

## Killing
Via the shared `ProcessTerminationService` (see [architecture](../architecture.md#safe-termination)): the exact socket
and the process identity are re-verified before SIGTERM; force kill is a separate explicit step that re-verifies again.

## Permissions
None to view. `lsof` only lists your own processes' sockets (sockets owned by other users aren't shown). You can only
terminate processes your user owns; root/system processes are marked protected.

## Limits
Sockets owned by other users or root daemons don't appear. `sudo lsof -nP -iTCP -sTCP:LISTEN` in Terminal shows all.
