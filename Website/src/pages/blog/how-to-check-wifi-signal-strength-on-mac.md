---
layout: ../../layouts/Article.astro
title: "How to Check Wi-Fi Signal Strength on Mac (RSSI) | MacPeek"
description: "Check your Mac's Wi-Fi signal strength, noise, channel and link speed with the Option-click menu, Wireless Diagnostics or Terminal, and how to read the numbers."
h1: "How to Check Wi-Fi Signal Strength on Mac"
section: blog
utility: netpeek
date: "2026-10-06"
---
## The quick way: Option-click the Wi-Fi menu
Hold **Option** and click the **Wi-Fi icon** in the menu bar. Under your network name you will see details including **RSSI** (signal strength), **Noise**, **Tx Rate** (link speed), **Channel** and **PHY Mode**.

## Wireless Diagnostics
1. Hold **Option**, click the Wi-Fi icon and choose **Open Wireless Diagnostics**.
2. Ignore the first window and choose **Window → Performance** from the menu bar.
3. Watch the signal and noise graph while you walk around.

## In Terminal
```bash
sudo wdutil info
```

This prints the current Wi-Fi details, including RSSI, noise and channel. Older guides use an `airport` command, which Apple has deprecated and which is not available in recent macOS versions.

## Reading RSSI
RSSI is measured in dBm; closer to zero is stronger.

| RSSI | Rough meaning |
|---|---|
| −30 to −50 | Excellent |
| −50 to −67 | Good, fine for most things |
| −67 to −70 | Marginal for video calls |
| −70 to −80 | Weak, expect drops |
| below −80 | Barely usable |

The gap between RSSI and **Noise** matters too: a signal-to-noise ratio of about 25 dB or more is healthy.

## If the signal is weak
- Move closer to the router, or remove obstacles between you and it.
- Prefer the **5 GHz** band when you are close; 2.4 GHz travels farther but is slower and more crowded.
- Try a different channel on the router if neighbours' networks overlap.

## Limits
Recent macOS versions may hide your network name unless an app has Location access; the signal numbers do not need it. These are readings at one moment, so check in several spots.
