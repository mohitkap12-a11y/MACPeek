#if os(macOS)
import SwiftUI
import MacPeekCore
import PortPeekKit

/// PortPeek's screen: search, scrollable port list with inline details and kill flow, status footer.
struct PortPeekView: View {
    @EnvironmentObject private var store: PortStore

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                SearchField(text: $store.query, prompt: "Search ports, processes or PIDs…")
                if store.isScanning { ProgressView().controlSize(.small) }
                Button { Task { await store.refresh() } } label: { Image(systemName: "arrow.clockwise") }
                    .buttonStyle(.borderless)
                    .help("Refresh now")
                    .keyboardShortcut("r", modifiers: .command)
                    .accessibilityLabel("Refresh")
                    .padding(.trailing, 12)
            }
            Divider()
            if let banner = store.banner { BannerView(banner: banner) }
            if let error = store.scanError, store.ports.isEmpty {
                ErrorState(message: error) { Task { await store.refresh() } }
            } else {
                PortListView()
            }
            Divider()
            footer
        }
    }

    private var footer: some View {
        HStack {
            let n = store.ports.count
            Text("\(n) listening port\(n == 1 ? "" : "s")")
            Spacer()
            if let error = store.scanError {
                Text(error).foregroundStyle(.red).lineLimit(1)
            } else if let updated = store.lastUpdated {
                Text("Updated ") + Text(updated, style: .relative).monospacedDigit() + Text(" ago")
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }
}

struct BannerView: View {
    let banner: Banner
    var body: some View {
        Text(banner.text)
            .font(.caption)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background((banner.kind == .success ? Color.green : Color.red).opacity(0.15))
            .transition(.opacity)
            .accessibilityAddTraits(.updatesFrequently)
    }
}
#endif
