#if os(macOS)
import SwiftUI
import USBPeekKit

/// USBPeek's screen: USB devices as a tree per bus, then Thunderbolt / USB4 ports.
struct USBPeekView: View {
    @EnvironmentObject private var store: USBStore

    var body: some View {
        VStack(spacing: 0) {
            content
            Divider()
            footer
        }
    }

    @ViewBuilder private var content: some View {
        if let error = store.error, store.snapshot == nil {
            ErrorState(message: error, retryTitle: "Try again") { store.refresh() }
        } else if let snapshot = store.snapshot {
            if snapshot.deviceCount == 0 && snapshot.thunderboltPorts.isEmpty {
                EmptyState(symbol: "cable.connector", title: "Nothing connected",
                           message: "No USB devices were reported by macOS.")
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) { sections(snapshot) }
                }
                .frame(maxHeight: .infinity)
            }
        } else {
            VStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Reading connected devices…").font(.caption).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    @ViewBuilder private func sections(_ snapshot: USBSnapshot) -> some View {
        let populated = snapshot.buses.filter { $0.deviceCount > 0 }
        ForEach(populated) { bus in
            SectionHeader(title: bus.title, detail: bus.controllerClass)
            ForEach(bus.devices) { device in USBDeviceRow(device: device, depth: 0) }
        }
        let idle = snapshot.buses.count - populated.count
        if idle > 0 {
            Text("\(idle) other USB controller\(idle == 1 ? "" : "s") with nothing connected")
                .font(.caption).foregroundStyle(.tertiary)
                .padding(.horizontal, 12).padding(.vertical, 6)
        }

        SectionHeader(title: "Thunderbolt / USB4 ports", detail: nil)
        if snapshot.thunderboltPorts.isEmpty {
            Text(snapshot.thunderboltNote ?? "No Thunderbolt ports reported.")
                .font(.caption).foregroundStyle(.secondary)
                .padding(.horizontal, 12).padding(.vertical, 6)
        } else {
            ForEach(snapshot.thunderboltPorts) { port in ThunderboltPortRow(port: port) }
        }
    }

    private var footer: some View {
        HStack {
            if let snapshot = store.snapshot {
                let n = snapshot.deviceCount
                Text("\(n) USB device\(n == 1 ? "" : "s")")
            } else {
                Text("Reads when you open it")
            }
            Spacer()
            if store.isLoading { ProgressView().controlSize(.small) }
            Button { store.refresh() } label: { Image(systemName: "arrow.clockwise") }
                .buttonStyle(.borderless)
                .help("Read again")
                .keyboardShortcut("r", modifiers: .command)
                .accessibilityLabel("Read connected devices again")
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }
}

private struct SectionHeader: View {
    let title: String
    let detail: String?

    var body: some View {
        HStack(spacing: 6) {
            Text(title).font(.caption.weight(.semibold))
            if let detail { Text(detail).font(.caption2).foregroundStyle(.tertiary).lineLimit(1) }
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.top, 10)
        .padding(.bottom, 4)
        .accessibilityAddTraits(.isHeader)
    }
}

private struct USBDeviceRow: View {
    @EnvironmentObject private var store: USBStore
    let device: USBDevice
    let depth: Int

    private var expanded: Bool { store.selectedID == device.id }

    private var rows: [(label: String, value: String)] {
        var rows: [(label: String, value: String)] = []
        if let value = device.vendorName { rows.append(("Vendor", value)) }
        if let value = device.vendorProductLabel { rows.append(("Vendor : product", value)) }
        if let value = device.speedLabel { rows.append(("Link speed", value)) }
        if let value = device.declaredUSBVersion { rows.append(("Declared USB version", value)) }
        if let value = device.deviceClassLabel { rows.append(("Device class", value)) }
        return rows
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: device.isHub ? "point.3.connected.trianglepath.dotted" : "cable.connector")
                    .foregroundStyle(.secondary)
                    .frame(width: 16)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 1) {
                    Text(device.name).font(.system(size: 13, weight: .medium)).lineLimit(1)
                    if let vendor = device.vendorName { Text(vendor).font(.caption).foregroundStyle(.secondary).lineLimit(1) }
                }
                Spacer(minLength: 4)
                if device.isHub { StatusBadge(text: "Hub") }
                if let speed = device.speedLabel { StatusBadge(text: speed, tone: .info) }
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.tertiary)
                    .rotationEffect(.degrees(expanded ? 90 : 0))
                    .accessibilityHidden(true)
            }
            .padding(.leading, 12 + CGFloat(depth) * 18)
            .padding(.trailing, 12)
            .padding(.vertical, 7)
            .contentShape(Rectangle())
            .onTapGesture { withAnimation(.easeOut(duration: 0.15)) { store.selectedID = expanded ? nil : device.id } }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isButton)

            if expanded {
                HStack(alignment: .top) {
                    KeyValueRows(rows: rows)
                    Spacer()
                    CopyButton(text: device.copyText, label: "Copy device details")
                }
                .padding(.leading, 12 + CGFloat(depth) * 18 + 24)
                .padding(.trailing, 12)
                .padding(.bottom, 8)
            }
            ForEach(device.children) { child in USBDeviceRow(device: child, depth: depth + 1) }
        }
        .background(expanded ? Color.accentColor.opacity(0.08) : .clear)
    }
}

private struct ThunderboltPortRow: View {
    let port: ThunderboltPort

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "bolt.horizontal").foregroundStyle(.secondary).frame(width: 16).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                Text(port.receptacle.map { "Port \($0)" } ?? port.busName).font(.system(size: 13, weight: .medium))
                Text(port.connectedDevices.isEmpty ? port.busName : port.connectedDevices.joined(separator: ", "))
                    .font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 4)
            StatusBadge(text: port.status, tone: port.isConnected ? .good : .neutral)
            if let speed = port.speed { StatusBadge(text: speed, tone: .info) }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .accessibilityElement(children: .combine)
    }
}
#endif
