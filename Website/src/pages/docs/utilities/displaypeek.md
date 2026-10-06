---
layout: ../../../layouts/Article.astro
title: "DisplayPeek: Resolution and Refresh Rate | MacPeek Docs"
description: "How to use DisplayPeek to see each display's real resolution, refresh rate and scaling on your Mac, and what it can and cannot tell you."
h1: "DisplayPeek"
section: docs
date: "2026-10-06"
---
**The question it answers:** what display configuration am I actually running?

## What you see
One card per connected display:

| Field | Meaning |
|---|---|
| Panel resolution | The display's native pixels |
| Looks like | The resolution macOS presents to your apps |
| Refresh rate | The rate macOS reports for the current mode |
| Scaling | Worked out from the two resolutions: native (1×), HiDPI (2×) or scaled |
| Main, mirrored, online | Shown only when macOS reports them |
| Vendor / product ID, manufactured | Identify the panel model and when it was made |

Anything else macOS reports about a display appears below as extra detail. If macOS does not report something, DisplayPeek leaves it out instead of guessing. It never infers cable type, HDR or connection protocol.

## How to use it
1. Open **DisplayPeek** from the launcher. It reads your display configuration when the screen opens.
2. Press `⌘R` after you change a setting or plug in a monitor to read again.
3. Use the copy button on a card to copy its details for a support thread.

## Good to know
- **Serial numbers are never read** or shown, so copied details are safe to share.
- "Rotation: Supported" means the display *can* rotate, not that it is rotated.
- A refresh rate below what the monitor advertises usually means a cable, adapter or the selected mode is the limit. See [check monitor refresh rate on Mac](/blog/how-to-check-monitor-refresh-rate-on-mac/).

## Privacy
Read-only. Nothing runs in the background and nothing is sent anywhere. See [permissions](/docs/permissions/).
