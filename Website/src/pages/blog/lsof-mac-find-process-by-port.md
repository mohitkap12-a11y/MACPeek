---
layout: ../../layouts/Article.astro
title: "lsof on Mac: Find a Process by Port (Cheat Sheet) | PortPeek"
description: "A practical lsof cheat sheet for macOS: find the process by port, list all listeners, filter by TCP or UDP, IPv4 or IPv6, and parse the output."
h1: "lsof on Mac: Find a Process by Port"
section: blog
date: "2026-10-06"
---
`lsof` ("list open files") treats network sockets as files, which makes it the standard way to map a port to a process on macOS.

## Core commands
| Goal | Command |
|---|---|
| Who listens on TCP 3000? | `lsof -nP -iTCP:3000 -sTCP:LISTEN` |
| All TCP listeners | `lsof -nP -iTCP -sTCP:LISTEN` |
| UDP on port 5353 | `lsof -nP -iUDP:5353` |
| IPv6 only | `lsof -nP -i6TCP -sTCP:LISTEN` |
| One process's sockets | `lsof -nP -a -p 18432 -i` |
| Only PIDs | `lsof -ti tcp:3000` |
| Everyone's sockets | `sudo lsof -nP -iTCP -sTCP:LISTEN` |

## Reading the output
```text
COMMAND   PID  USER  FD  TYPE  DEVICE NODE NAME
node    18432 mohit 23u  IPv4  0x1f2  TCP  *:3000 (LISTEN)
```
- `NAME`: `*:3000` is all interfaces, `127.0.0.1:3000` localhost only.
- `FD`: file descriptor; `u` means opened read/write.
- `COMMAND` is truncated to 9 characters unless you pass `+c 0`.

## Machine-readable output
```bash
lsof -nP +c 0 -iTCP -sTCP:LISTEN -FpcLn
```
`-F` prints one field per line (`p` pid, `c` command, `L` user, `n` name), which is far more robust to parse than columns. PortPeek uses this format internally.

## Gotchas
- Without `-n -P` lsof resolves names and can be slow.
- Plain `-i :3000` also matches outgoing connections to port 3000.
- No `sudo`, no other users' processes.

Prefer a UI? [PortPeek](/) wraps this in a searchable menu-bar list.
