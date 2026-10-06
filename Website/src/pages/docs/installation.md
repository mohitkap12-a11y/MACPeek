---
layout: ../../layouts/Article.astro
title: "Install MacPeek on Mac | MacPeek Docs"
description: "Install MacPeek on macOS: download the DMG, drag it to Applications, launch it and find it in the menu bar. Verify the download with SHA256SUMS."
h1: "Installing MacPeek"
section: docs
date: "2026-10-06"
---
MacPeek needs **macOS 13 (Ventura) or later**, on Apple silicon or Intel. PortPeek, the port finder, is one of the utilities inside MacPeek.

## Steps
1. Download `MacPeek-x.y.z.dmg` from the [latest release](https://github.com/mohitkap12-a11y/MACPeek/releases/latest).
2. Open the DMG.
3. Drag **MacPeek** to **Applications**.
4. Launch MacPeek.
5. The MacPeek icon appears in the menu bar. There is no Dock icon and no main window by design.

## Verify the download
Each release publishes a `SHA256SUMS` file next to the DMG. Download both into the same folder, then run:

```bash
cd ~/Downloads
shasum -a 256 -c --ignore-missing SHA256SUMS
```

You should see `MacPeek-x.y.z.dmg: OK`. Releases are Developer ID signed and notarized by Apple, so Gatekeeper opens them without warnings.

## Launch at login
Open MacPeek, click the gear icon and enable **Launch at login**. This works when the app is run from `/Applications`.

## Choose your utilities
Open **Manage utilities** from the launcher to see every utility, what it reads and what access it needs, and to switch each one on or off.

## Uninstall
Quit MacPeek from the menu-bar icon (right-click → Quit), then delete it from Applications. Settings live in `~/Library/Preferences/app.macpeek.MacPeek.plist`.

Next: [how to use PortPeek](/docs/usage/).
