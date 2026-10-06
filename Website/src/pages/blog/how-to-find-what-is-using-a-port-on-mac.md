---
layout: ../../layouts/Article.astro
title: "How to Find What Is Using a Port on Mac | MacPeek"
description: "Find which process is using a port on macOS with lsof or netstat, read the output, and see the same answer from your menu bar with PortPeek."
h1: "How to Find What Is Using a Port on Mac"
section: blog
utility: portpeek
date: "2026-10-06"
---
Seeing `EADDRINUSE` or "port already in use"? Something on your Mac is already listening on that port. Here is how to find out what.

## The quick answer: lsof
```bash
lsof -nP -iTCP:3000 -sTCP:LISTEN
```

Example output:

```text
COMMAND   PID   USER   FD   TYPE   NODE NAME
node    18432  mohit   23u  IPv4    TCP 127.0.0.1:3000 (LISTEN)
```

The `COMMAND` and `PID` columns identify the process. The flags: `-n` and `-P` skip slow DNS and service-name lookups, `-iTCP:3000` selects TCP port 3000, and `-sTCP:LISTEN` keeps only listeners.

The short form `lsof -i :3000` also works, but it includes outgoing connections to that port too, which can be confusing.

## Processes owned by other users
`lsof` only shows what your user may inspect. For system services use `sudo`:

```bash
sudo lsof -nP -iTCP:80 -sTCP:LISTEN
```

## List every listening port
```bash
lsof -nP -iTCP -sTCP:LISTEN
```

## Alternative: netstat
```bash
netstat -anv -p tcp | grep LISTEN | grep 3000
```
This shows the PID in its own column but is harder to read, and macOS's `netstat` has no `-p` process option like Linux.

## UDP
```bash
lsof -nP -iUDP:5353
```

## The problem with the Terminal workflow
You have to remember the flags, switch windows, read columns, then run a second command to stop the process. Every time.

## Faster: PortPeek
PortPeek shows every listening port in your menu bar. Type `3000` and you see the process and PID instantly. Next step: [kill the process](/blog/how-to-kill-a-process-on-a-port-on-mac/).
