#if os(macOS)
import SwiftUI
import AppKit
import StartupPeekKit
import MacPeekCore

/// StartupPeek's screen: a searchable, read-only inventory grouped by kind. Every row says where it was found, and the
/// screen states what it cannot see. There is deliberately no enable/disable/remove control.
struct StartupPeekView: View {
    @EnvironmentObject private var store: StartupStore

    var body: some View {
        VStack(spacing: 0) {
            SearchField(text: $store.query, prompt: "Search startup items…")
            Divider()
            if let error = store.error, store.inventory != nil {
                BannerView(banner: Banner(kind: .error, text: "Couldn't refresh: \(error) Showing the last reading."))
            }
            content
            Divider()
            footer
        }
    }

    @ViewBuilder private var content: some View {
        if let error = store.error, store.inventory == nil {
            ErrorState(message: error, retryTitle: "Try again") { store.refresh() }
        } else if let inventory = store.inventory {
            let items = store.filteredItems
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if items.isEmpty {
                        Text(store.query.isEmpty ? "No startup items were found in the places MacPeek can read."
                                                 : "No startup items match “\(store.query)”.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    ForEach(StartupCategory.allCases, id: \.self) { category in
                        let group = items.filter { $0.category == category }
                        if !group.isEmpty {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("\(category.sectionTitle.uppercased()) (\(group.count))")
                                    .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                                    .accessibilityAddTraits(.isHeader)
                                Text(category.explanation).font(.caption2).foregroundStyle(.tertiary)
                                ForEach(group) { item in ItemCard(item: item) }
                            }
                        }
                    }
                    LimitationsCard(limitations: inventory.limitations)
                }
                .padding(12)
            }
            .frame(maxHeight: .infinity)
        } else {
            VStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Reading startup items…").font(.caption).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var footer: some View {
        HStack(spacing: 8) {
            Text(store.inventory.map { "Read-only · \($0.items.count) found · not a complete list" } ?? "Read-only · reads when you open it")
            Spacer()
            if store.isLoading { ProgressView().controlSize(.small) }
            Button("Login Items Settings") { SystemSettingsOpener.open(.loginItems) }
                .buttonStyle(.borderless)
                .accessibilityLabel("Open Login Items and Extensions settings")
            Button { store.refresh() } label: { Image(systemName: "arrow.clockwise") }
                .buttonStyle(.borderless)
                .help("Read again")
                .keyboardShortcut("r", modifiers: .command)
                .accessibilityLabel("Read startup items again")
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }
}

private struct ItemCard: View {
    let item: StartupItem
    @State private var expanded = false

    private var tone: StatusBadge.Tone {
        switch item.status {
        case .enabled, .startsAutomatically: return .good
        case .requiresApproval, .disabledInFile: return .warning
        default: return .neutral
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(item.name).font(.system(size: 13, weight: .semibold)).lineLimit(1)
                    if let line = item.attributionLine, line != "Likely associated with \(item.name)" {
                        Text(line).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
                Spacer(minLength: 4)
                StatusBadge(text: item.status.label, tone: tone)
                CopyButton(text: item.copyText, label: "Copy details for \(item.name)")
            }
            Text("\(item.category.label) · \(item.scope.label) · found via \(item.source.rawValue)")
                .font(.caption2).foregroundStyle(.secondary).lineLimit(2)
            ForEach(item.observations, id: \.self) { note in
                Label(note, systemImage: "info.circle").font(.caption2).foregroundStyle(.secondary)
            }
            HStack(spacing: 8) {
                if let path = [item.executablePath, item.propertyListPath].compactMap({ $0 }).first(where: { FileManager.default.fileExists(atPath: $0) }) {
                    Button("Reveal") { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)]) }
                        .accessibilityLabel("Reveal \(item.name) in Finder")
                }
                Button(expanded ? "Hide details" : "Details") { expanded.toggle() }
                    .accessibilityLabel(expanded ? "Hide details for \(item.name)" : "Show details for \(item.name)")
                if item.category == .loginItem || item.category == .backgroundItem {
                    Button("Open Login Items Settings") { SystemSettingsOpener.open(.loginItems) }
                }
            }
            .controlSize(.small)
            if expanded { KeyValueRows(rows: details) }
        }
        .peekCard()
        .accessibilityElement(children: .contain)
    }

    private var details: [(label: String, value: String)] {
        var rows: [(label: String, value: String)] = [("Developer", item.signature.summary)]
        if let label = item.label { rows.append(("Label", label)) }
        if let path = item.executablePath { rows.append(("Executable", path)) }
        if let path = item.propertyListPath { rows.append(("Property list", path)) }
        if let app = item.associatedApp { rows.append(("Likely associated with", app)) }
        rows.append(("What this means", item.category.explanation))
        return rows
    }
}

private struct LimitationsCard: View {
    let limitations: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label("What StartupPeek cannot see", systemImage: "eye.slash").font(.caption.weight(.semibold))
            ForEach(limitations, id: \.self) { text in
                Text(text).font(.caption2).foregroundStyle(.secondary)
            }
        }
        .peekCard()
        .accessibilityElement(children: .combine)
    }
}
#endif
