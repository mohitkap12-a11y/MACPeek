---
layout: ../../layouts/Article.astro
title: "How to Kill a Process on a Port on Mac | PortPeek"
description: "Kill the process using a port on macOS: find the PID with lsof, stop it with kill, escalate to kill -9 only if needed, and verify the port is free."
h1: "How to Kill a Process on a Port on Mac"
section: blog
date: "2026-10-06"
---
## Step 1: find the PID
```bash
lsof -nP -iTCP:8080 -sTCP:LISTEN
```
Note the number in the `PID` column.

## Step 2: ask it to quit (SIGTERM)
```bash
kill 18232
```
`kill` without options sends SIGTERM, which lets the program close files and connections cleanly.

## Step 3: force it only if needed
```bash
kill -9 18232
```
SIGKILL ends the process immediately and cannot be caught, so unsaved data and temp files are not cleaned up. Use it only if SIGTERM was ignored.

## One-liner
```bash
kill $(lsof -ti tcp:8080 -sTCP:LISTEN)
```
`-t` prints only PIDs. Be careful: if nothing matches, an empty `kill` fails harmlessly, but if several processes match they are all signalled.

## Step 4: verify
```bash
lsof -nP -iTCP:8080 -sTCP:LISTEN   # no output means the port is free
```

## "Operation not permitted"
The process belongs to another user. Use `sudo kill <pid>` only if you are sure what it is.

## Pitfall: stale PIDs
PIDs are recycled. If you copy a PID, wait, then `kill -9` it, you may hit an unrelated process. PortPeek re-checks the port owner and the process start time right before signalling, tries SIGTERM first, and only force-kills when you explicitly confirm — see [how it works](/docs/killing-processes/).
