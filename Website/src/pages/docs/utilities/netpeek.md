---
layout: ../../../layouts/Article.astro
title: "NetPeek: Check Your Network Connection | MacPeek Docs"
description: "How to use NetPeek to see your active connection, Wi-Fi signal and DNS servers, and run on-demand ping checks against your router and DNS servers."
h1: "NetPeek"
section: docs
date: "2026-10-06"
---
**The question it answers:** is my network connection actually healthy?

## What you see
- **The connection:** the interface your traffic uses ("Wi-Fi", "Ethernet"…), its IPv4 and IPv6 addresses, your router and your DNS servers. Other connections, such as VPNs, are collapsed below.
- **Wi-Fi**, when the active interface is Wi-Fi: signal and noise in dBm, the difference between them, channel and band, standard, link rate and security.
- **Connection checks**, only when you press **Run checks**.

## How to use it
1. Open **NetPeek**. The connection refreshes every few seconds while the screen is open, and Wi-Fi details load once per visit.
2. Press **Run checks** to ping your router and up to three of your DNS servers, three pings each, side by side. Only IPv4 servers are pinged; IPv6 ones are listed as skipped.
3. Read the findings. Each is labelled **Measured or reported** (a ping result, a signal reading) or **Likely (inference)**, such as "lost packets to the router often mean a weak signal".

## Good to know
- **The Wi-Fi network name shows as hidden.** macOS hides it from apps without Location access, and MacPeek does not request it.
- The signal band (Excellent, Good, Fair, Weak) is a common rule of thumb, not something macOS reports.
- No reply to a ping is never presented as proof of an outage: some devices ignore pings.
- The link rate is what the radio negotiated, not your internet speed. NetPeek runs no speed tests.

## Privacy
The checks run **only when you press the button**, and go only to your router and your DNS servers. DNS servers are often outside your home network (a public resolver, your ISP), so those pings do leave it. Results are discarded when you leave the screen. See [Check Wi-Fi signal strength on Mac](/blog/how-to-check-wifi-signal-strength-on-mac/).
