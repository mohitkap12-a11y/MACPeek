#if os(macOS)
import SwiftUI
import PortPeekCore

struct MainPopoverView: View {
    @EnvironmentObject private var store: PortStore
    @State private var showSettings = false

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if showSettings {
                SettingsView()
            } else {
                SearchBar(text: $store.query)
                Divider()
                if let banner = store.banner { BannerView(banner: banner) }
                PortListView()
                Divider()
                footer
            }
        }
        .frame(width: 380, height: 520)
        .background(.background)
    }

    private var header: some View {
        HStack(spacing: 8) {
            Text(showSettings ? "Settings" : "PortPeek")
                .font(.system(size: 14, weight: .semibold))
            Spacer()
            if store.isScanning { ProgressView().controlSize(.small) }
            if !showSettings {
                Button { Task { await store.refresh() } } label: { Image(systemName: "arrow.clockwise") }
                    .help("Refresh now")
                    .keyboardShortcut("r", modifiers: .command)
            }
            Button { showSettings.toggle() } label: { Image(systemName: showSettings ? "xmark" : "gearshape") }
                .help(showSettings ? "Back to ports" : "Settings")
        }
        .buttonStyle(.borderless)
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
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
    }
}
#endif
