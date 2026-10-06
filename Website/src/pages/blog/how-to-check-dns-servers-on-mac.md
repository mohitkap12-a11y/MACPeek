---
layout: ../../layouts/Article.astro
title: "How to Check Your DNS Servers on Mac | MacPeek"
description: "See which DNS servers your Mac uses and test whether each one answers, with System Settings, scutil, dig and DNSPeek. Includes how to flush the DNS cache."
h1: "Check Your DNS Servers on Mac"
section: blog
utility: dnspeek
date: "2026-10-06"
---
Pages load slowly, a site will not resolve, or a VPN breaks internal names. First find out which DNS servers your Mac is actually using.

## In System Settings
Open **System Settings → Network**, select your connection, click **Details…** and choose **DNS**. If the list is empty, your Mac uses the servers your router hands out.

## In Terminal
The full picture, including per-domain servers from a VPN:
```bash
scutil --dns
```
Look at `resolver #1`: its `nameserver[0]`, `nameserver[1]`… are the servers used for ordinary names, in order. Entries with a `domain` are only used for that domain.

Servers you set by hand for a connection:
```bash
networksetup -listallnetworkservices
networksetup -getdnsservers Wi-Fi
```
"There aren't any DNS Servers set" means automatic.

## Test a server
Resolve a name the way apps do:
```bash
dscacheutil -q host -a name apple.com
```
Ask one server directly, with a short timeout:
```bash
dig @1.1.1.1 apple.com A +time=2 +tries=1
```
Look at `status:` (`NOERROR` is a normal answer, `NXDOMAIN` means the name does not exist) and `Query time`. A timeout means that server did not answer. If one of your servers times out while others answer, remove or fix it.

## Flush the cache
If a name resolves to an old address:
```bash
sudo dscacheutil -flushcache; sudo killall -HUP mDNSResponder
```

## Why VPNs and filters change the answer
VPNs and DNS-filtering apps can add resolvers for specific domains or answer on a local address. Then the server that answers is not the one in your network settings.

## With DNSPeek
DNSPeek lists the servers in use, their interface and reachability, search domains and per-domain resolvers, then **Run lookup** resolves a name and asks each server directly (up to four), showing who answered, how fast and with what status. It never changes settings, and lookups run only when you press the button. See the [DNSPeek docs](/docs/utilities/dnspeek/).
