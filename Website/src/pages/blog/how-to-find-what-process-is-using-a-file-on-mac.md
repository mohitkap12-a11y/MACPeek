---
layout: ../../layouts/Article.astro
title: "How to Find What Process Is Using a File on Mac | MacPeek"
description: "Fix 'the item is in use' and drives that won't eject: find which process has a file or folder open on macOS with lsof or Activity Monitor, and how to release it safely."
h1: "How to Find What Process Is Using a File on Mac"
section: blog
utility: filelockpeek
date: "2026-10-06"
---
You try to delete a file, empty the Trash or eject a drive and macOS says the item is **in use**, but not by whom. Something has it open. Here is how to find it.

## Find the process with lsof
For a single file:

```bash
lsof /path/to/file
```

For a folder, including everything inside it (this can be slow on big folders):

```bash
lsof +D /path/to/folder
```

Example output:

```text
COMMAND    PID  USER   FD   TYPE  NAME
Docker   18432 mohit   23u  REG   /Users/mohit/data.db
sqlite3  20311 mohit    4r  REG   /Users/mohit/data.db
```

`COMMAND` and `PID` identify the process. The `FD` column tells you **how** it holds the path.

## Reading the FD column
| FD | Meaning |
|---|---|
| `3r`, `4w`, `5u` | an open file: read, write or read/write |
| `5uW` | the same, plus a lock (the letter after the mode: `W` is a write lock on the whole file) |
| `cwd` | the process's current working directory is here |
| `txt` | the file is the program the process is running |
| `mem` | the file is memory-mapped, for example a loaded library |

## A drive that will not eject
Ask lsof about the whole volume:

```bash
lsof /Volumes/MyDrive
```

When you give lsof a mount point it lists every open file on that volume, which is faster than `+D`. Typical culprits are Spotlight indexing the drive, a Terminal tab whose working directory is on it (`cd` out of it), Preview, Photos or a backup tool.

## Other users' processes
`lsof` only shows your own processes. For others, such as system services, use `sudo lsof /path/to/file`.

## Without Terminal: Activity Monitor
Select a process in Activity Monitor, click the **ⓘ** (Inspect) button and open the **Open Files and Ports** tab. That works when you already suspect a process, but not when you want to ask "who has *this* file?".

## Releasing the file
1. Quit the app normally first. That is almost always enough.
2. If it will not quit, ask it to stop with `kill <PID>`, which sends SIGTERM and lets it clean up.
3. Use `kill -9` only as a last resort: it cannot save state, and a stale PID may by now belong to a different process. See [how MacPeek checks before it kills](/docs/killing-processes/).
4. Run `lsof` again to confirm nothing holds the file.

## Tip
If the holder is a Terminal session or editor, closing the window or `cd`-ing elsewhere releases a folder without killing anything.
