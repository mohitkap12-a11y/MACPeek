# ContainerPeek

**Question:** Which containers and VMs are running, and what are they costing me?

## What it shows
- Per container engine (**Docker** and **Podman**), with the Docker context in use (Docker Desktop, OrbStack, Colima and
  Rancher Desktop each add one): every container, running first, with its image, state, published ports, Compose project
  and service, and the CPU and memory the engine reports for it.
- When the engine is installed but not running ("Cannot connect to the Docker daemon"), that is shown as **not running**, not
  as an error and never as "no containers".
- **Virtual machines** from **Lima**, **Colima**, **Tart** and **Parallels Desktop** when their tools are installed: name, state,
  CPUs, assigned memory and disk.
- **Hypervisor processes** on the Mac (Apple's Virtualization framework, QEMU, Parallels, VMware, Docker Desktop, OrbStack,
  Podman's vfkit/krunkit) with the CPU and memory macOS counts for them. This is the real cost of a VM on the Mac,
  whichever tool started it, and covers VMs (UTM, for example) whose tool MacPeek does not ask.
- On request, a container's **last 200 log lines**.

## Management
Start, Stop, Restart, Pause, Resume and Remove, offered only in states where they apply (Remove only for a stopped
container). Stop, Restart and Remove ask for an inline confirmation. Before acting, ContainerPeek lists the container again
by its full ID and refuses if it is gone, has been renamed, or is now in a state where the action does not apply. Each action
is one engine command with a fixed argument list and the full, validated ID (`docker stop <64 hex characters>`), run as your
user, never through a shell. Remove is `docker rm <id>`: never `--force`, never `--volumes`, and images are untouched.

## How it works
Fixed tool locations only (a menu-bar app has no shell PATH): `/opt/homebrew/bin`, `/usr/local/bin`, Docker Desktop's
`Contents/Resources/bin`, `~/.orbstack/bin`, `~/.rd/bin`, `/opt/podman/bin` and Parallels' app bundle.

| What | Command |
|---|---|
| Containers | `docker ps --all --no-trunc --format '{{json .}}'`, `podman ps --all --format json` |
| Resource use | `docker stats --no-stream --no-trunc --format '{{json .}}'`, `podman stats --no-stream --format json` (only when a container is running) |
| Context | `docker context show` |
| VMs | `limactl list --json`, `colima list --json`, `tart list --format json`, `prlctl list --all --json` |
| Hypervisor processes | the shared libproc reader (`proc_pid_rusage`); CPU over the interval between two reads |
| Logs | `docker logs --tail 200 <id>` only when you press Show recent logs |

Reads run every *refresh interval* (at least 5 s, because `stats` takes a second or two) while the screen is open and
stop when you leave it. The launcher summary ("3 containers, 1 VM running") lists containers and VMs only: it never runs
`stats` or the process scan.

## Privacy
Container logs can contain secrets: they are shown on screen, can be copied, and are never saved or logged; leaving the
screen forgets them. Container environment variables and `inspect` output are never read.

## Fact versus inference
CPU and memory are the engine's own figures (a single reading). Hypervisor CPU is sampled by MacPeek and labelled as such.
Which hypervisor process belongs to which tool is inferred from the process name.

## Verified against
**Not yet verified on a Mac.** Fixtures in `Tests/ContainerPeekKitTests/Fixtures/` were written from the tools' documented
JSON output; `scripts/capture-fixtures.sh` now captures the real output to replace them before release. Podman field names
vary between versions; the parser accepts both spellings it knows of.
