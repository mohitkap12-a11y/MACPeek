# USBPeek

**Question:** What is connected, and at what speed?

## What it shows
- **USB devices as a tree per bus.** Hubs contain the devices behind them. Each device shows its name, vendor, and (when
  expanded) vendor:product ID, **link speed**, the USB version it declares, and its device class.
- **Thunderbolt / USB4 ports**: status ("No device connected" or the state macOS reports), speed ("Up to 40 Gb/s") and any
  devices macOS lists on the port.

| Field | Source |
|---|---|
| Link speed | `UsbLinkSpeed` in bits per second (480 000 000 → "480 Mb/s", 5 000 000 000 → "5 Gb/s") |
| Declared USB version | `bcdUSB`, binary-coded decimal (0x0320 → "3.20"). This is what the *device* declares, not proof of the port or cable |
| Device class | `bDeviceClass` (9 = Hub; 0 = "Defined per interface") |
| Vendor, product | `USB Vendor Name` / `kUSBVendorString`, `USB Product Name` / `kUSBProductString`, `idVendor`, `idProduct` |

## How it works
`ioreg -p IOUSB -l -w0` parsed by `IORegUSBParser` (controllers at depth 1, `IOUSBHostDevice` entries below them), and
`system_profiler SPThunderboltDataType -json` for Thunderbolt ports. A Thunderbolt failure never hides USB results.

USB comes from `ioreg` rather than `system_profiler SPUSBDataType` because the latter returned an empty list on a Mac that
had devices attached.

## Privacy
**Serial numbers are never read.** The parser only keeps an allow-list of properties and additionally drops any key containing
"serial", so a serial cannot be displayed, copied or logged.

## Refresh
Reads when the screen opens, then every few seconds (at least 3 s, following the refresh setting) **only while the screen is open**, so plugging or unplugging a device shows up without reopening it. ⌘R reads immediately; there is no launcher summary. Only the newest read may update the screen, and leaving the screen stops polling and cancels a running read.

## Limits
- It shows what macOS reports. A device that negotiated a slow speed may be limited by its cable, port or hub: USBPeek shows the
  result, not the cause.
- Devices attached through some docks or hubs are listed under the hub's bus as macOS presents them.
- The Thunderbolt `_items` structure for *connected* devices was not available for verification; device names are read
  defensively and an unreadable section shows "Thunderbolt information is not available on this Mac".

## Verified against
A Mac mini (Mac14,3) with three hubs and a mouse. Fixtures: `Tests/USBPeekKitTests/Fixtures/`.
