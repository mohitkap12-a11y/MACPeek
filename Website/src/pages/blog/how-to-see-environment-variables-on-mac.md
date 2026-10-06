---
layout: ../../layouts/Article.astro
title: "How to See Environment Variables on Mac | MacPeek"
description: "List and inspect environment variables and PATH on macOS in Terminal, see why GUI apps see different values, and inspect a running process with EnvPeek."
h1: "See Environment Variables on Mac"
section: blog
utility: envpeek
date: "2026-10-06"
---
A command works in one terminal but not in another, or an app cannot find a tool. The cause is usually the environment it started with.

## In Terminal
```bash
printenv            # all variables
printenv PATH       # one variable
env | sort          # sorted list
echo "$PATH" | tr ':' '\n'    # PATH, one folder per line
which -a node       # every match for a command, in PATH order
```
The order in `PATH` matters: the first folder that contains the command wins.

## Why apps see different values
Variables you set in `~/.zshrc` exist only in shells that read that file. Apps you open from Finder, the Dock or at login do **not** run your shell startup files, so they usually see far fewer variables. That is why an editor launched from the Dock can miss tools your terminal finds.

Which file runs when (zsh): `~/.zshenv` for every shell, `~/.zprofile` for login shells, `~/.zshrc` for interactive shells.

To read a variable from the login session that GUI apps inherit:
```bash
launchctl getenv NAME
```

## A running process
For a process you own, you can see the environment it started with:
```bash
ps eww -p 12345
```
macOS hides this for protected system programs, and it never shows variables a process set after it started.

## Careful with secrets
Environment variables often hold tokens and passwords. Do not paste `printenv` output into bug reports or chats.

## With EnvPeek
EnvPeek shows **this app's** environment and, for a PID you enter, **a process's** environment, always labelled so the two are not confused. It opens `PATH` entry by entry and flags duplicates, missing folders and relative entries. Values that look like credentials stay hidden until you press **Reveal**, and nothing is logged or stored. See the [EnvPeek docs](/docs/utilities/envpeek/).
