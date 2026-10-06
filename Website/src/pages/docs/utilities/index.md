---
layout: ../../../layouts/Article.astro
title: "MacPeek Utilities: Overview | MacPeek Docs"
description: "Every MacPeek utility at a glance: the question each one answers, what it reads from your Mac, what it can change and where to find its guide."
h1: "Utilities overview"
section: docs
date: "2026-10-06"
---
MacPeek is a set of small, focused utilities in one menu-bar app. Each answers one question, reads only what it needs, and does nothing in the background while its screen is closed.

| Utility | Answers | Can it change anything? |
|---|---|---|
| [PortPeek](/docs/ports/) | What is using this port? | Ends a process you own, after safety checks |
| [FileLockPeek](/docs/utilities/filelockpeek/) | What process is using this file? | Ends a process you own, after safety checks |
| [ProcessPeek](/docs/utilities/processpeek/) | What exactly is this process? | Ends a process you own, after safety checks |
| [DiskPeek](/docs/utilities/diskpeek/) | Which app is using my disk? | No, read-only |
| [EnvPeek](/docs/utilities/envpeek/) | What environment does this see? | No, read-only |
| [NetPeek](/docs/utilities/netpeek/) | Is my connection healthy? | No. Pings only when you ask |
| [DNSPeek](/docs/utilities/dnspeek/) | Which DNS servers, and do they respond? | No. Lookups only when you ask |
| [DisplayPeek](/docs/utilities/displaypeek/) | What display setup am I running? | No, read-only |
| [USBPeek](/docs/utilities/usbpeek/) | What is connected, and how fast? | No, read-only |
| [SleepPeek](/docs/utilities/sleeppeek/) | Why isn't my Mac sleeping? | No, read-only |

**BatteryPeek** (battery health and cycle count) is planned and not released yet. See [all utilities](/utilities/) for what each reads and needs.

## Rules every utility follows
- **Runs as you.** No administrator rights, ever. See [permissions](/docs/permissions/).
- **Facts versus guesses.** Anything read from macOS is labelled as such. Explanations are labelled **Likely (inference)**.
- **Never guesses missing data.** A detail macOS does not report is left out.
- **Nothing leaves your Mac.** No account, no telemetry. The two utilities that touch the network, NetPeek and DNSPeek, do so only when you press a button, and tell you exactly where requests go.
- **Nothing is ended for you.** Utilities that can end a process use the shared [safe termination](/docs/killing-processes/) steps.
