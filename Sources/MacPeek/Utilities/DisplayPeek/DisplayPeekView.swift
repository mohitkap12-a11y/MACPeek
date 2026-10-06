#if os(macOS)
import SwiftUI
import DisplayPeekKit

/// DisplayPeek's screen: one card per connected display with what macOS reports about it.
struct DisplayPeekView: View {
    @EnvironmentObject private var store: DisplayStore

    var body: some View {
        VStack(spacing: 0) {
            content
            Divider()
            footer
        }
    }

    @ViewBuilder private var content: some View {
        if let error = store.error, store.report == nil {
            ErrorState(message: error, retryTitle: "Try again") { store.refresh() }
        } else if let report = store.report {
            if report.displays.isEmpty {
                EmptyState(symbol: "display.trianglebadge.exclamationmark", title: "No displays reported",
                           message: "macOS did not list any display.")
            } else {
                ScrollView {
                    VStack(spacing: 10) {
                        ForEach(report.displays) { display in DisplayCard(display: display) }
                    }
                    .padding(12)
                }
                .frame(maxHeight: .infinity)
            }
        } else {
            VStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Reading display information…").font(.caption).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var footer: some View {
        HStack {
            let n = store.report?.displays.count ?? 0
            Text(store.report == nil ? "Reads when you open it" : "\(n) display\(n == 1 ? "" : "s")")
            if let gpu = store.report?.gpus.first {
                Text("· \(gpu.name)").lineLimit(1)
            }
            Spacer()
            if store.isLoading { ProgressView().controlSize(.small) }
            Button { store.refresh() } label: { Image(systemName: "arrow.clockwise") }
                .buttonStyle(.borderless)
                .help("Read again")
                .keyboardShortcut("r", modifiers: .command)
                .accessibilityLabel("Read display information again")
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }
}

private struct DisplayCard: View {
    let display: DisplayInfo

    private var rows: [(label: String, value: String)] {
        var rows: [(label: String, value: String)] = []
        if let value = display.nativeResolution { rows.append(("Panel resolution", value)) }
        if let value = display.uiResolution { rows.append(("Looks like", value)) }
        if let value = display.refreshLabel { rows.append(("Refresh rate", value)) }
        if display.scaling != .unknown { rows.append(("Scaling", display.scaling.label)) }
        if let value = display.isMain { rows.append(("Main display", value ? "Yes" : "No")) }
        if let value = display.isMirrored { rows.append(("Mirrored", value ? "Yes" : "No")) }
        if let value = display.isOnline { rows.append(("Online", value ? "Yes" : "No")) }
        if let vendor = display.vendorID, let product = display.productID { rows.append(("Vendor / product ID", "\(vendor) / \(product)")) }
        if let value = display.manufactured { rows.append(("Manufactured", value)) }
        for detail in display.details { rows.append((detail.label, detail.value)) }
        return rows
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                IconTile(symbol: "display")
                VStack(alignment: .leading, spacing: 1) {
                    Text(display.name).font(.system(size: 13, weight: .semibold)).lineLimit(1)
                    if let gpu = display.gpuName { Text(gpu).font(.caption).foregroundStyle(.secondary) }
                }
                Spacer(minLength: 4)
                if let hz = display.refreshLabel { StatusBadge(text: hz, tone: .info) }
                if display.isMain == true { StatusBadge(text: "Main", tone: .good) }
                CopyButton(text: display.copyText, label: "Copy display details")
            }
            Divider().opacity(0.5)
            KeyValueRows(rows: rows)
        }
        .peekCard()
        .accessibilityElement(children: .contain)
    }
}
#endif
