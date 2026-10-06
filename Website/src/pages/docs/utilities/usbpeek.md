---
layout: ../../../layouts/Article.astro
title: "USBPeek: See USB Devices and Speeds | MacPeek Docs"
description: "How to use USBPeek to see every USB and Thunderbolt device on your Mac, the speed each one negotiated, and why a fast drive can be running slow."
h1: "USBPeek"
section: docs
date: "2026-10-06"
---
**The question it answers:** what is connected, and at what speed?

## What you see
- **USB devices as a tree per bus.** Hubs contain the devices behind them. Each device shows its name and vendor; expand it for the vendor:product ID, **link speed**, the USB version it declares and its device class.
- **Thunderbolt / USB4 ports** below, with their status ("No device connected" or what macOS reports) and speed.

| Field | Meaning |
|---|---|
| Link speed | What macOS negotiated with the device, for example 480 Mb/s or 5 Gb/s |
| Declared USB version | What the *device* says it supports. It is not proof of the port or cable |
| Device class | The kind of device, for example hub or storage |

## How to use it
1. Open **USBPeek**. It reads when the screen opens and then **updates every few seconds while the screen is open**, so plugging or unplugging a device shows up without reopening it.
2. Click a device to see its details and copy them.
3. Press `⌘R` to read immediately.

## Good to know
- If a fast drive seems slow, check its link speed. A device that negotiated 480 Mb/s on a 10 Gb/s port is usually limited by its cable, hub or its own USB version. USBPeek shows the result, not the cause.
- Devices attached through docks and hubs appear under the hub, as macOS presents them.
- If Thunderbolt information is unavailable on your Mac, USB devices are still listed.

## Privacy
**Serial numbers are never read**, displayed, copied or logged. Read-only, and nothing runs when the screen is closed. See [See USB devices on Mac](/blog/how-to-see-usb-devices-on-mac/).
