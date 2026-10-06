# DisplayPeek

**Question:** What display configuration am I actually running?

## What it shows
One card per connected display:

| Field | Source |
|---|---|
| Name, GPU | `_name`, the adapter's `sppci_model` |
| Panel resolution | `_spdisplays_pixels` (the panel's native pixels) |
| Looks like, Refresh rate | `spdisplays_resolution` / `_spdisplays_resolution` ("3440 x 1440 @ 100.00Hz") |
| Scaling | worked out from the two resolutions: native (1×), HiDPI (2×) or scaled (other factors) |
| Main display, Mirrored, Online | `spdisplays_main`, `spdisplays_mirror`, `spdisplays_online` (shown only when macOS reports them) |
| Vendor / product ID, Manufactured | `_spdisplays_display-vendor-id`, `-product-id`, `-year`, `-week` |
| Everything else | any other string field macOS reports, shown humanised (for example `Rotation: Supported`) |

macOS reports `spdisplays_rotation: spdisplays_supported`, meaning rotation is *supported*, not that the display is rotated, so
that is exactly how it is labelled.

## How it works
`system_profiler SPDisplaysDataType -json`, parsed by `DisplayParser` into `DisplayReport`. Every field is optional: a key
macOS does not report stays empty and is not shown. DisplayPeek never infers cable type, HDR or protocol.

## Privacy
Serial numbers (any key containing "serial") are dropped by the parser and are not in the model, the UI or the copied text.

## Refresh
Reads when the screen opens and when you press ⌘R; nothing runs in the background and there is no launcher summary.
Leaving the screen cancels a running read.

## Verified against
A Mac mini (Mac14,3, Apple M2) with one ultrawide display. Fixture: `Tests/DisplayPeekKitTests/Fixtures/mac_mini_one_display.txt`.
Laptop built-in displays and multi-display setups report extra keys that were not available when this was written; they appear
under "everything else" automatically, and contributions of real captures (`scripts/capture-fixtures.sh`) are welcome.
