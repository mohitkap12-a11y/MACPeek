#if os(macOS)
import SwiftUI
import SoundPeekKit
import MacPeekCore

/// SoundPeek's screen: the default output and input, then every device that can do each. Only controls the device
/// actually exposes are shown; anything else reads "Not reported".
struct SoundPeekView: View {
    @EnvironmentObject private var store: SoundStore

    var body: some View {
        VStack(spacing: 0) {
            if let banner = store.banner {
                HStack(spacing: 8) {
                    BannerView(banner: banner)
                    if store.lastChange != nil, banner.kind == .success {
                        Button("Undo") { store.undo() }.controlSize(.small).accessibilityLabel("Restore the previous device")
                    }
                    Button { store.dismissBanner() } label: { Image(systemName: "xmark") }
                        .buttonStyle(.borderless).accessibilityLabel("Dismiss message")
                }
                .padding(.trailing, 12)
            }
            if let error = store.error, store.snapshot != nil {
                BannerView(banner: Banner(kind: .error, text: "Couldn't refresh: \(error) Showing the last reading."))
            }
            content
            Divider()
            footer
        }
    }

    @ViewBuilder private var content: some View {
        if let error = store.error, store.snapshot == nil {
            ErrorState(message: error, retryTitle: "Try again") { store.refresh() }
        } else if let snapshot = store.snapshot {
            if snapshot.devices.isEmpty {
                EmptyState(symbol: "speaker.slash", title: "No audio devices reported",
                           message: "macOS did not list any audio device.")
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        DirectionSection(snapshot: snapshot, direction: .output)
                        DirectionSection(snapshot: snapshot, direction: .input)
                        let others = snapshot.devicesWithoutDirection
                        if !others.isEmpty {
                            Text("Other devices").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                            ForEach(others) { device in
                                Text(snapshot.displayNames()[device.id] ?? device.name).font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .padding(12)
                }
                .frame(maxHeight: .infinity)
            }
        } else {
            VStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Reading audio devices…").font(.caption).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var footer: some View {
        HStack(spacing: 8) {
            if let updated = store.snapshot?.updatedAt {
                Text("Updated \(updated.formatted(date: .omitted, time: .standard)) · never records audio")
            } else {
                Text("Never records or listens to audio")
            }
            Spacer()
            if store.isLoading { ProgressView().controlSize(.small) }
            if let snapshot = store.snapshot {
                CopyButton(text: snapshot.diagnosticReport(macOSVersion: ProcessInfo.processInfo.operatingSystemVersionString),
                           label: "Copy audio report")
            }
            Button("Sound Settings") { SystemSettingsOpener.open(.sound) }
                .buttonStyle(.borderless)
                .accessibilityLabel("Open Sound settings")
            Button { store.refresh() } label: { Image(systemName: "arrow.clockwise") }
                .buttonStyle(.borderless)
                .help("Read again")
                .keyboardShortcut("r", modifiers: .command)
                .accessibilityLabel("Read audio devices again")
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }
}

private struct DirectionSection: View {
    let snapshot: AudioSnapshot
    let direction: AudioDirection

    var body: some View {
        let devices = snapshot.devices(for: direction)
        let names = snapshot.displayNames()
        VStack(alignment: .leading, spacing: 8) {
            Text(direction.label.uppercased()).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                .accessibilityAddTraits(.isHeader)
            if devices.isEmpty {
                Text("No \(direction.label.lowercased()) devices").font(.caption).foregroundStyle(.tertiary)
            }
            ForEach(devices) { device in
                DeviceCard(device: device, name: names[device.id] ?? device.name, direction: direction,
                           isDefault: device.id == snapshot.defaultID(direction))
            }
        }
    }
}

private struct DeviceCard: View {
    @EnvironmentObject private var store: SoundStore
    let device: AudioDevice
    let name: String
    let direction: AudioDirection
    let isDefault: Bool

    private var controls: AudioControls { device.controls(direction) }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                IconTile(symbol: symbol)
                VStack(alignment: .leading, spacing: 1) {
                    Text(name).font(.system(size: 13, weight: .semibold)).lineLimit(1)
                    Text(device.transport.label).font(.caption).foregroundStyle(.secondary)
                }
                Spacer(minLength: 4)
                if isDefault { StatusBadge(text: "Default", tone: .good) }
            }
            KeyValueRows(rows: rows)
            HStack(spacing: 8) {
                if !isDefault {
                    Button("Set as default \(direction.label.lowercased())") { store.setDefault(device.id, direction: direction) }
                        .controlSize(.small)
                        .accessibilityLabel("Make \(name) the default \(direction.label.lowercased()) device")
                }
                if controls.canSetMute {
                    Button((controls.isMuted ?? false) ? "Unmute" : "Mute") { store.toggleMute(device, direction: direction) }
                        .controlSize(.small)
                        .accessibilityLabel("\((controls.isMuted ?? false) ? "Unmute" : "Mute") \(name)")
                }
            }
        }
        .peekCard()
        .accessibilityElement(children: .contain)
    }

    private var symbol: String {
        switch device.transport {
        case .bluetooth, .bluetoothLE: return "headphones"
        case .hdmi, .displayPort: return "display"
        case .usb, .thunderbolt: return "cable.connector"
        case .airPlay: return "airplayaudio"
        default: return direction == .input ? "mic" : "speaker.wave.2"
        }
    }

    private var rows: [(label: String, value: String)] {
        [
            ("Format", device.formatLabel(direction) ?? "Not reported"),
            ("Volume", controls.volumeLabel ?? "Not exposed by this device"),
            ("Muted", controls.isMuted.map { $0 ? "Yes" : "No" } ?? "Not exposed by this device"),
        ]
    }
}
#endif
