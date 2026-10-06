---
layout: ../../layouts/Article.astro
title: "See USB Devices and Check Their Speed on Mac | MacPeek"
description: "List the USB and Thunderbolt devices connected to your Mac with System Information or Terminal, read the link speed, and spot a slow cable or port."
h1: "How to See USB Devices on Mac"
section: blog
utility: usbpeek
date: "2026-10-06"
---
Is that SSD on a fast port, or is something limiting it? macOS can tell you, but the answer is a few clicks deep.

## In System Information
1. Hold **Option** and open the **Apple menu**, then choose **System Information** (or go to **System Settings → General → About → System Report**).
2. In the sidebar under **Hardware**, choose **USB**. Choose **Thunderbolt/USB4** for Thunderbolt devices.
3. Select a device to see its vendor, product and **Speed**.

## In Terminal
```bash
system_profiler SPUSBDataType
system_profiler SPThunderboltDataType
```

The USB output is a tree: controllers and hubs with the devices below them. The `Speed:` line shows the speed negotiated for that device.

## Reading the speed
| You see | Roughly |
|---|---|
| 480 Mb/s | USB 2.0 |
| Up to 5 Gb/s | USB 3.x Gen 1 |
| Up to 10 Gb/s | USB 3.x Gen 2 |
| Up to 20 Gb/s | USB 3.2 Gen 2x2 |
| 40 Gb/s | Thunderbolt 3, 4 or USB4 |

## A fast drive showing a slow speed
- **Cable:** many USB-C cables only carry USB 2.0 speeds. Use a cable rated for the speed you expect.
- **Port or hub:** a hub may be limiting every device behind it. Plug the drive straight into the Mac.
- **The drive itself:** it may simply not support the faster speed.

## Privacy note
System reports can include serial numbers. Remove them before pasting a report into a public bug report or forum post.
