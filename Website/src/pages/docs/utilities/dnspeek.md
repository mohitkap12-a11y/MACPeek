---
layout: ../../../layouts/Article.astro
title: "DNSPeek: Which DNS Servers Am I Using? | MacPeek Docs"
description: "How to use DNSPeek to see the DNS servers and search domains macOS uses, run a lookup and ask each server directly to find the one that is slow or failing."
h1: "DNSPeek"
section: docs
date: "2026-10-06"
---
**The question it answers:** which DNS servers is my Mac using, and do they respond?

## What you see
- **DNS servers in use:** the servers macOS asks for ordinary names, in order, with the interface and reachability macOS reports.
- **Search domains**, and **per-domain resolvers** (names under one domain go to specific servers, common with VPNs).
- A note for **multicast DNS** (`.local` names answered on your network) and **scoped** resolvers (bound to one interface).

## How to use it
1. Open **DNSPeek**. It reads the configuration when the screen opens; press `⌘R` to read again.
2. Type a name (apple.com by default) and press **Run lookup**. DNSPeek resolves it the way apps do, then asks each active server directly (up to four).
3. See who answered, how fast and with what status. A server that times out while others answer is the one to fix or remove.
4. Copy the configuration for a support thread.

## Good to know
- The system lookup time covers the whole run and may be a cache hit, so it is labelled "about".
- A VPN or DNS-filtering app (for example Cloudflare WARP) can answer from a local address instead of the servers you configured. DNSPeek shows what macOS reports and what the server answers.
- Anything DNSPeek cannot read is shown as "unavailable", never guessed.

## Privacy and safety
DNSPeek is read-only and never changes DNS settings. Lookups run **only when you press the button**, and only the name you typed is queried. Names and server addresses are validated before anything is run. Results are discarded when you leave the screen.
