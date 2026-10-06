---
layout: ../../layouts/Article.astro
title: "How to Free Port 3000 on Mac (Port Already in Use) | MacPeek"
description: "Fix 'port 3000 already in use' on Mac: find the process with lsof, kill it, or use a different port. Works for Node, React, Next.js and Rails dev servers."
h1: "How to Free Port 3000 on Mac"
section: blog
utility: portpeek
date: "2026-10-06"
---
Dev servers for Node, Express, Create React App, Next.js and Rails commonly default to port 3000. If a previous run didn't shut down, you get:

```text
Error: listen EADDRINUSE: address already in use :::3000
```

## Fix it in Terminal
```bash
lsof -nP -iTCP:3000 -sTCP:LISTEN     # find the PID
kill <PID>                            # polite stop
```
Or in one step:
```bash
kill $(lsof -ti tcp:3000 -sTCP:LISTEN)
```
Still running? `kill -9 <PID>` as a last resort. Confirm with the first command again.

## Why it happens
- A previous `npm start` was suspended (`Ctrl+Z`) instead of stopped.
- A terminal tab closed but the child process lived on.
- Another project's server is on 3000.

## Don't want to kill it?
Run on another port: `PORT=3001 npm start` (varies by framework, e.g. `next dev -p 3001`).

## Without Terminal
Open [PortPeek](/utilities/portpeek/) from the menu bar, type `3000`, and click **Kill Process**. You see which app owns the port first, and PortPeek confirms the port is free afterwards.
