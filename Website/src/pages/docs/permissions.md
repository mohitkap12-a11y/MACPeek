---
layout: ../../layouts/Article.astro
title: "Permissions and Protected Processes | MacPeek Docs"
description: "Why MacPeek utilities can't kill or read some things: it runs as your user, never elevates privileges, and marks protected or permission-restricted processes."
h1: "Permissions"
section: docs
date: "2026-10-06"
---
MacPeek runs as **your user** and never asks for administrator rights, not even to display ports. Each utility lists the access it needs on its page and in **Manage utilities**; most need none.

## Indicators
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
