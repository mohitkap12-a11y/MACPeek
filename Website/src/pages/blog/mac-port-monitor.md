---
layout: ../../layouts/Article.astro
title: "Mac Port Monitor: Watch Listening Ports Live | MacPeek"
description: "Monitor which ports are listening on your Mac in real time: with a shell loop, or with PortPeek's live-updating list in the MacPeek menu bar app."
h1: "Monitor Listening Ports on Mac"
section: blog
utility: portpeek
date: "2026-10-06"
---
Want to watch ports appear and disappear while you start services? Two approaches.

## Terminal: poll lsof
```bash
while true; do clear; lsof -nP -iTCP -sTCP:LISTEN | sort -k9; sleep 2; done
```
Works, but it occupies a terminal, redraws everything, and can't search.

## Menu bar: PortPeek
Open PortPeek from the MacPeek menu-bar icon and the list refreshes every 2 seconds (configurable, 1–10 s) **only while PortPeek's screen is open** — it doesn't poll in the background, so it's safe to leave running all day.

Typical uses:
- Confirm your dev server actually bound the port you expected.
- Spot a leftover process after a crash.
- Check whether something is listening on all interfaces (`*`) instead of just localhost.

PortPeek watches ports only; for CPU or memory use Activity Monitor. Learn more in the [docs](/docs/ports/).
