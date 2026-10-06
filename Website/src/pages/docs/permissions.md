---
layout: ../../layouts/Article.astro
title: "Permissions and Protected Processes | PortPeek Docs"
description: "Why PortPeek can't kill some processes: it runs as your user, never elevates privileges, and marks protected or permission-restricted processes."
h1: "Permissions"
section: docs
date: "2026-10-06"
---
PortPeek runs as **your user** and never asks for administrator rights, not even to display ports.

## Indicators
- ✓ **Can terminate** — owned by your user.
- ⚠ **Permission required** — owned by another user; the kernel will refuse the signal.
- 🔒 **Protected/system process** — root-owned, PID 1 or PortPeek itself; the Kill button is disabled.

## Why a kill can fail
macOS only lets a process signal processes with the same user ID (unless root). If termination fails you'll see:

```text
Permission denied. postgres (PID 921) cannot be terminated by the current user.
```

PortPeek will not silently elevate. If you really need to stop a root-owned process, use Terminal deliberately: `sudo kill <pid>`.

## Notifications and login item
Notifications are optional (off with one toggle). Launch at login uses Apple's `SMAppService` and can be revoked in System Settings → General → Login Items.
