#if os(macOS)
import SwiftUI
import MacPeekCore

/// Lists every utility with a plain description and an on/off switch.
struct UtilityManagerView: View {
    @EnvironmentObject private var router: UtilityRouter

    var body: some View {
        VStack(spacing: 0) {
            PeekHeader(title: "Utilities", subtitle: "Choose what appears in MacPeek", onBack: { router.back() })
            Divider()
            ScrollView {
                VStack(spacing: 10) {
                    ForEach(UtilityCatalog.all) { info in UtilityCard(info: info) }
                }
                .padding(12)
            }
        }
    }
}

private struct UtilityCard: View {
    let info: UtilityInfo
    @EnvironmentObject private var registry: UtilityRegistry
    @State private var expanded = false

    private var enabled: Binding<Bool> {
        Binding(get: { registry.isEnabled(info.id) }, set: { registry.setEnabled(info.id, $0) })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 12) {
                IconTile(symbol: info.icon, size: 34)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(info.name).font(.system(size: 13, weight: .semibold))
                        if !info.isAvailable { StatusBadge(text: "Coming soon", tone: .info) }
                    }
                    Text(info.tagline).font(.caption).foregroundStyle(.secondary)
                }
                Spacer(minLength: 4)
                Toggle("Enable \(info.name)", isOn: enabled)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .disabled(!info.isAvailable || registry.anyModule(for: info.id) == nil)
            }
            DisclosureGroup("Learn more", isExpanded: $expanded) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(info.question).font(.caption).italic().foregroundStyle(.secondary)
                    Text(info.summary).font(.caption)
                    bullets("What it reads", info.reads)
                    bullets("Access it needs", info.permissions)
                    Text("Everything stays on your Mac: no account, no telemetry, no network access.")
                        .font(.caption2).foregroundStyle(.secondary)
                }
                .padding(.top, 6)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .font(.caption)
        }
        .peekCard()
        .accessibilityElement(children: .contain)
    }

    private func bullets(_ title: String, _ items: [String]) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary)
            ForEach(items, id: \.self) { Text("• \($0)").font(.caption) }
        }
    }
}
#endif
