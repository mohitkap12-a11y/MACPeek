---
layout: ../../layouts/Article.astro
title: "Permissions and Protected Processes | MacPeek Docs"
description: "Why MacPeek utilities can't kill or read some things: it runs as your user, never elevates privileges, and marks protected or permission-restricted processes."
h1: "Permissions"
section: docs
date: "2026-10-06"
---
MacPeek runs as **your user** and never asks for administrator rights, not even to display ports or processes. Each utility lists the access it needs on its page and in **Manage utilities**; most need none.

## What each utility needs
| Utility | Permission needed | Limits you may notice |
|---|---|---|
| PortPeek | None | Other users' and root sockets are not listed |
| FileLockPeek | None | Other users' processes are not listed |
| ProcessPeek | None | Other users' processes are hidden by default; some details of protected processes are unavailable |
| DiskPeek | None | Other users' and protected processes cannot be read; DiskPeek shows how many it skipped |
| EnvPeek | None | A process's environment can be read only for your own, non-protected processes |
| NetPeek | None | The Wi-Fi network name is hidden by macOS (MacPeek does not request Location access) |
| DNSPeek | None | None |
| DisplayPeek, USBPeek, SleepPeek | None | Serial numbers are never read |

No utility asks for Full Disk Access, Accessibility, Screen Recording or Location.

## Indicators (utilities that can end a process)
- ✓ **Can terminate** — owned by your user.
- ⚠ **Permission required** — owned by another user; the kernel will refuse the signal.
- 🔒 **Protected/system process** — root-owned, PID 1 or MacPeek itself; the Kill button is disabled.

## Why a kill can fail
macOS only lets a process signal processes with the same user ID (unless root). If termination fails you'll see:

```text
Permission denied. postgres (PID 921) cannot be terminated by the current user.
```

MacPeek will not silently elevate. If you really need to stop a root-owned process, use Terminal deliberately: `sudo kill <pid>`.

## Notifications and login item
Notifications are optional (off with one toggle). Launch at login uses Apple's `SMAppService` and can be revoked in System Settings → General → Login Items.
