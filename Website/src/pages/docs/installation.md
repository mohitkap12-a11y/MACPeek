---
layout: ../../layouts/Article.astro
title: "Install PortPeek on Mac | PortPeek Docs"
description: "Install PortPeek on macOS: download the DMG, drag it to Applications, launch it and find it in the menu bar. Verify the SHA-256 checksum."
h1: "Installing PortPeek"
section: docs
date: "2026-10-06"
---
PortPeek needs **macOS 13 (Ventura) or later**, on Apple silicon or Intel.

## Steps
1. Download `PortPeek-x.y.z.dmg` from the [latest release](https://github.com/mohitkap12-a11y/MACPeek/releases/latest).
2. Open the DMG.
3. Drag **PortPeek** to **Applications**.
4. Launch PortPeek.
5. The PortPeek icon appears in the menu bar. There is no Dock icon and no main window by design.

## Verify the download
Each release publishes a SHA-256 checksum next to the DMG:

```bash
shasum -a 256 ~/Downloads/PortPeek-1.0.0.dmg
```

Compare the output to the `.sha256` file on the release page. Releases are Developer ID signed and notarized by Apple, so Gatekeeper opens them without warnings.

## Launch at login
Open PortPeek, click the gear icon and enable **Launch at login**. This works when the app is run from `/Applications`.

## Uninstall
Quit PortPeek from the menu-bar icon (right-click → Quit), then delete it from Applications. Settings live in `~/Library/Preferences/app.portpeek.PortPeek.plist`.

Next: [how to use PortPeek](/docs/usage/).
