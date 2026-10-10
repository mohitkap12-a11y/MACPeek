# SoundPeek

**Question:** Why is my audio going to the wrong place?
**Non-goals:** recording, monitoring or metering audio; per-app volume or routing; "fix audio" actions; virtual drivers.

## What it shows
- The current **default output** and **default input** device, and every device that can do each direction (default first).
- Per device: connection type (built-in, USB, Bluetooth, HDMI, …), sample rate, channel count, volume and mute state.
- On the **default output** device only: a **volume slider** (where the device reports a writable volume) and a **Mute** button (where mute is writable). Other devices show their volume and mute state read-only.
- Anything a device does not expose reads **Not reported** / **Not exposed by this device**. Nothing is estimated.
- Duplicate device names are told apart (`USB Audio (1)`, `Headset (Bluetooth)`).
- Copy audio report: names, connection, formats, defaults. No device IDs, UIDs or serial numbers.

## What it can change (only when you press a button)
- **Set as default input/output** for a device that has that direction. **Undo** appears right after a switch and restores
  the previous device if it is still connected. SoundPeek never switches devices on its own, including when a new one appears.
- **Mute / Unmute** only on the default output device, and only where Core Audio reports the mute property as writable. Make a device the default first to mute it.
- **Volume slider** (0–100%) only on the default output device, and only where Core Audio reports the volume property as writable (the device's main volume, or both
  channel 1 and 2 on devices that only have per-channel volume). Changes are sent shortly after you stop moving, the last
  value wins, and the slider shows your value until the device confirms it. Moving the slider does not change mute and keeps
  the default-device Undo.

## Data sources and APIs
Core Audio (Audio Hardware) property API via `CoreAudioDeviceProvider`: `kAudioHardwarePropertyDevices`,
`…DefaultInputDevice`/`…DefaultOutputDevice`, `kAudioObjectPropertyName`, `kAudioDevicePropertyTransportType`,
`…StreamConfiguration`, `…NominalSampleRate`, `…VolumeScalar` (read and write), `…Mute` (read and write), `…IsHidden`. Property listeners
(`CoreAudioChangeObserver`) are registered only while the screen is visible and removed when it is left. Reads run off the
main thread. Hidden devices are not listed. Device IDs are runtime identifiers only and are never stored.

## Permissions and privacy
None. No audio stream is ever opened, so macOS never asks for Microphone access. No network. Device names are never logged.

## Minimum macOS
13 (uses `kAudioObjectPropertyElementMain`).

## Known limitations
- Many HDMI/DisplayPort and some USB devices do not expose volume or mute to macOS; they show "Not exposed by this device"
  and get no slider.
- Volume/mute changed outside SoundPeek (menu bar, keyboard) appears on the next device-change event or Refresh; there are
  no per-device property listeners.
- Per-app volume/mute and "which app is using audio" were investigated and **not shipped**: see
  [the capability report](../next-peeks-capability-report.md#soundpeek).
- No input level meter (it would require capturing audio).

## Testing
`swift test --filter SoundPeekKitTests` (fake provider: mapping, unavailable properties, duplicate names, removal, errors,
undo, volume clamping and refusal for read-only or removed devices). Manual: built-in devices, USB headset, Bluetooth, HDMI/monitor audio, unplug/replug while open, sleep/wake, a device
without volume/mute.
