#if os(macOS)
import SwiftUI
import MacPeekCore

/// The main screen: a launcher for the utilities the user has enabled (not a metrics dashboard).
struct LauncherView: View {
    @EnvironmentObject private var registry: UtilityRegistry
    @EnvironmentObject private var router: UtilityRouter
    @State private var query = ""

    private var visible: [UtilityInfo] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return registry.enabledUtilities }
        return registry.enabledUtilities.filter {
            $0.name.lowercased().contains(q) || $0.tagline.lowercased().contains(q) || $0.question.lowercased().contains(q)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            PeekHeader(title: "MacPeek") {
                Button { router.go(.settings) } label: { Image(systemName: "gearshape") }
                    .help("Settings")
                    .accessibilityLabel("Settings")
            }
            Divider()
            if registry.enabledUtilities.isEmpty {
                EmptyState(
                    symbol: "square.grid.2x2", title: "No utilities enabled",
                    message: "Turn on the utilities you want in the menu bar.",
                    actionTitle: "Manage utilities", action: { router.go(.manage) }
                )
            } else {
                SearchField(text: $query, prompt: "Search utilities…")
                Divider()
                if visible.isEmpty {
                    EmptyState(symbol: "magnifyingglass", title: "No matching utilities")
                } else {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 0) {
                            ForEach(UtilityCategory.allCases, id: \.self) { category in
                                let items = visible.filter { $0.category == category }
                                if !items.isEmpty {
                                    Text(category.rawValue.uppercased())
                                        .font(.system(size: 10, weight: .semibold))
                                        .foregroundStyle(.secondary)
                                        .padding(.horizontal, 12)
                                        .padding(.top, 12)
                                        .padding(.bottom, 4)
                                        .accessibilityAddTraits(.isHeader)
                                    ForEach(items) { info in
                                        PeekRow(
                                            icon: info.icon, title: info.name,
                                            subtitle: registry.summaries[info.id] ?? info.tagline
                                        ) { router.go(.utility(info.id)) }
                                    }
                                }
                            }
                        }
                        .padding(.bottom, 8)
                    }
                }
            }
            Divider()
            footer
        }
    }

    private var footer: some View {
        HStack {
            Button { router.go(.manage) } label: { Label("Manage utilities", systemImage: "switch.2") }
            Spacer()
            Text("\(registry.selection.enabledCount) of \(registry.selection.availableCount) on")
                .font(.caption).foregroundStyle(.secondary)
            Spacer()
            Button("About") { router.go(.about) }
        }
        .buttonStyle(.borderless)
        .font(.caption)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
}
#endif
