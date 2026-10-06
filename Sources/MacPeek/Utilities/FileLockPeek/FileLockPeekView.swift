#if os(macOS)
import SwiftUI
import AppKit
import UniformTypeIdentifiers
import MacPeekCore
import FileLockPeekKit

/// FileLockPeek's screen: choose (or drop, or paste) a file or folder, then see what holds it open.
struct FileLockPeekView: View {
    @EnvironmentObject private var store: FileLockStore
    @State private var dropTargeted = false

    var body: some View {
        VStack(spacing: 0) {
            pathBar
            Divider()
            if let banner = store.banner { BannerView(banner: banner) }
            content
            Divider()
            footer
        }
        .overlay {
            if dropTargeted {
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(Color.accentColor, style: StrokeStyle(lineWidth: 2, dash: [6]))
                    .padding(6)
                    .allowsHitTesting(false)
            }
        }
        .onDrop(of: [UTType.fileURL], isTargeted: $dropTargeted) { providers in
            guard let provider = providers.first else { return false }
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                guard let url else { return }
                Task { @MainActor in store.scan(path: url.path) }
            }
            return true
        }
    }

    private var pathBar: some View {
        HStack(spacing: 6) {
            Image(systemName: "doc.text.magnifyingglass").foregroundStyle(.secondary).accessibilityHidden(true)
            TextField("Path to a file or folder…", text: $store.pathText)
                .textFieldStyle(.plain)
                .autocorrectionDisabled()
                .onSubmit { store.scan() }
                .accessibilityLabel("Path to a file or folder")
            if store.isScanning { ProgressView().controlSize(.small) }
            Button("Choose…", action: choose)
            Button { store.rescan() } label: { Image(systemName: "arrow.clockwise") }
                .buttonStyle(.borderless)
                .help("Scan again")
                .keyboardShortcut("r", modifiers: .command)
                .accessibilityLabel("Scan again")
                .disabled(store.pathText.trimmingCharacters(in: .whitespaces).isEmpty)
        }
        .controlSize(.small)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    @ViewBuilder private var content: some View {
        if let error = store.scanError {
            ErrorState(message: error, retryTitle: "Try again") { store.rescan() }
        } else if !store.hasScanned {
            EmptyState(
                symbol: "lock.doc", title: "Choose a file or folder",
                message: "Drop one here, paste a path, or click Choose…\nFolder scans include everything inside and can take a moment.",
                actionTitle: "Choose…", action: choose
            )
        } else if store.holders.isEmpty {
            EmptyState(
                symbol: "checkmark.circle", title: "Nothing is holding it open",
                message: "Only processes owned by your user account are visible to MacPeek."
            )
        } else {
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(store.holders) { holder in
                        FileHolderRowView(holder: holder)
                        Divider().opacity(0.4)
                    }
                }
            }
            .frame(maxHeight: .infinity)
        }
    }

    private var footer: some View {
        HStack {
            let n = store.holders.count
            if store.hasScanned && store.scanError == nil {
                Text("\(n) process\(n == 1 ? "" : "es")")
            } else {
                Text("Scans only when you ask")
            }
            Spacer()
            if let path = store.scannedPath {
                Text(URL(fileURLWithPath: path).lastPathComponent).lineLimit(1).truncationMode(.middle)
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }

    private func choose() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.showsHiddenFiles = true
        panel.prompt = "Find holders"
        if panel.runModal() == .OK, let url = panel.url { store.scan(path: url.path) }
    }
}
#endif
