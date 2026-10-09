#if os(macOS)
import SwiftUI
import PrivacyPeekKit

/// PrivacyPeek's screen: what each macOS privacy permission means, with a button to open its System Settings pane.
/// It shows no per-app status and never requests, reads or changes a permission.
struct PrivacyPeekView: View {
    @State private var expanded: Set<String> = []
    @State private var openFailed = false

    private let categories = PrivacyCatalog.categories(forMajorVersion: ProcessInfo.processInfo.operatingSystemVersion.majorVersion)

    var body: some View {
        VStack(spacing: 0) {
            if openFailed {
                BannerView(banner: Banner(kind: .error, text: PrivacyCatalog.openFailed))
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    VStack(alignment: .leading, spacing: 4) {
                        Label("Information only", systemImage: "info.circle").font(.caption.weight(.semibold))
                        Text(PrivacyCatalog.disclaimer).font(.caption2).foregroundStyle(.secondary)
                        Text(PrivacyCatalog.notAVerdict).font(.caption2).foregroundStyle(.secondary)
                    }
                    .peekCard()
                    .accessibilityElement(children: .combine)

                    ForEach(categories) { category in
                        CategoryCard(category: category, isExpanded: expanded.contains(category.id),
                                     toggle: { toggle(category.id) }, open: { open(category) })
                    }
                }
                .padding(12)
            }
            .frame(maxHeight: .infinity)
        }
    }

    private func toggle(_ id: String) {
        if expanded.contains(id) { expanded.remove(id) } else { expanded.insert(id) }
    }

    private func open(_ category: PrivacyCategory) {
        openFailed = !SystemSettingsOpener.open(category.pane)
    }
}

private struct CategoryCard: View {
    let category: PrivacyCategory
    let isExpanded: Bool
    let toggle: () -> Void
    let open: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                IconTile(symbol: category.symbol)
                VStack(alignment: .leading, spacing: 1) {
                    Text(category.name).font(.system(size: 13, weight: .semibold))
                    Text(category.summary).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                }
                Spacer(minLength: 4)
                Button(isExpanded ? "Hide" : "Learn", action: toggle)
                    .accessibilityLabel(isExpanded ? "Hide explanation of \(category.name)" : "Learn about \(category.name)")
                Button("Open Settings", action: open)
                    .accessibilityLabel("Open \(category.name) settings in System Settings")
            }
            .controlSize(.small)
            if isExpanded {
                Text(category.whatItAllows).font(.caption)
                if let note = category.note { Text(note).font(.caption2).foregroundStyle(.secondary) }
                Text("macOS controls the actual authorization. Review and change it in System Settings.")
                    .font(.caption2).foregroundStyle(.tertiary)
            }
        }
        .peekCard()
        .accessibilityElement(children: .contain)
    }
}
#endif
