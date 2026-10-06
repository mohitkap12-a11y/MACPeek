# Real screenshots for the website

Until real captures exist, every "screen" on the site is an **illustration** drawn from data
(`src/components/UtilityPreview.astro`, sample values only; the launcher is `LauncherMock.astro`). Pages for
utilities that have not shipped say so next to their illustration.

`AppShot.astro` switches to a real image automatically: if `public/screenshots/<name>.png` exists at build time, that
image is used instead of the illustration. **No code change is needed.**

## How to capture (on a Mac)
1. Run MacPeek (`swift run MacPeek`, or the built app) and open the utility.
2. Press `⌘⇧4`, then `Space`, then click the popover. Hold `Option` while clicking to drop the window shadow if you prefer.
3. Save the PNG as `Website/public/screenshots/<name>.png`:

| File | Shows |
|---|---|
| `portpeek.png` | PortPeek with a port expanded (home page + `/utilities/portpeek/`) |
| `displaypeek.png`, `usbpeek.png`, `netpeek.png`, `batterypeek.png`, `sleeppeek.png`, `filelockpeek.png`, `processpeek.png`, `diskpeek.png`, `envpeek.png`, `dnspeek.png` | Each utility, **only once it has shipped** |

Tips: capture at 2x (Retina), about 380 px wide, in dark mode to match the site; trim personal data (hostnames, paths,
serial numbers) before committing. Only add a utility's screenshot after that utility actually ships, and flip it to
`available` in `Sources/MacPeekCore/Registry/UtilityCatalog.swift` and `src/data/utilities.ts` in the same change
(`tests/catalog.test.mjs` fails if they drift).
