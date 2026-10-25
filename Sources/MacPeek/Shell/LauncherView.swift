#if os(macOS)
import SwiftUI
import MacPeekCore

/// The main screen: ring tiles for CPU, Memory and Disk, then every other enabled utility as a row, grouped by
/// category, with a search field. The values are the one-shot readings taken when the popover opened; the last ones
/// stay on screen until the new ones arrive, so the launcher never opens empty.
struct LauncherView: View {
    @EnvironmentObject private var registry: UtilityRegistry
    @EnvironmentObject private var router: UtilityRouter
    @EnvironmentObject private var settings: AppSettings
    @Environment(\.colorScheme) private var colorScheme
    @State private var query = ""

    /// The listed utilities that match the search, in catalog order.
    private var rows: [UtilityInfo] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return registry.tileUtilities }
        return registry.tileUtilities.filter {
            $0.name.lowercased().contains(q) || $0.tagline.lowercased().contains(q) || $0.question.lowercased().contains(q)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            if registry.enabledUtilities.isEmpty {
                EmptyState(
                    symbol: "square.grid.2x2", title: "No utilities enabled",
                    message: "Turn on the utilities you want in the menu bar.",
                    actionTitle: "Manage utilities", action: { router.go(.manage) }
                )
            } else {
                ScrollView {
                    VStack(spacing: 10) {
                        if !registry.gaugeUtilities.isEmpty {
                            HStack(spacing: 10) {
                                ForEach(registry.gaugeUtilities) { info in
                                    GaugeTile(info: info, gauge: registry.gauges[info.id]) { router.go(.utility(info.id)) }
                                }
                            }
                        }
                        if !registry.tileUtilities.isEmpty {
                            SearchField(text: $query, prompt: "Search utilities…")
                                .themedCard(radius: 10, padding: 0)
                            if rows.isEmpty {
                                Text("No matching utilities").font(.caption).foregroundStyle(PeekTheme.muted)
                                    .frame(maxWidth: .infinity).padding(.vertical, 16)
                            }
                            ForEach(UtilityCategory.allCases, id: \.self) { category in
                                let items = rows.filter { $0.category == category }
                                if !items.isEmpty {
                                    UtilitySection(title: category.rawValue, items: items)
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.bottom, 12)
                }
            }
            footer
        }
        .background(PeekTheme.ground)
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "waveform.path.ecg")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(PeekTheme.accent)
                .frame(width: 32, height: 32)
                .themedCard(radius: 9, padding: 0)
                .accessibilityHidden(true)
            Text("MacPeek").font(.system(size: 17, weight: .semibold))
            Spacer()
            HeaderButton(symbol: colorScheme == .dark ? "sun.max" : "moon",
                         label: colorScheme == .dark ? "Switch to light appearance" : "Switch to dark appearance") {
                settings.appearance = colorScheme == .dark ? .light : .dark
            }
            HeaderButton(symbol: "gearshape", label: "Settings") { router.go(.settings) }
        }
        .padding(.horizontal, 14)
        .padding(.top, 14)
        .padding(.bottom, 12)
    }

    private var footer: some View {
        HStack {
            Button("Manage utilities") { router.go(.manage) }
            Spacer()
            Text("\(registry.selection.enabledCount) of \(registry.selection.availableCount) on")
            Spacer()
            Button { router.go(.support) } label: { Label("Support", systemImage: "heart") }
                .help("Support MacPeek")
            Button("About") { router.go(.about) }
        }
        .buttonStyle(.borderless)
        .font(.caption)
        .foregroundStyle(PeekTheme.muted)
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .overlay(alignment: .top) { Rectangle().fill(PeekTheme.border).frame(height: 1) }
    }
}

private struct HeaderButton: View {
    let symbol: String
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .medium))
                .frame(width: 32, height: 32)
                .themedCard(radius: 9, padding: 0)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(label)
        .accessibilityLabel(label)
    }
}

/// CPU, Memory or Disk: a ring with the reading, the name, and one line of context.
private struct GaugeTile: View {
    let info: UtilityInfo
    let gauge: LauncherGauge?
    let action: () -> Void

    private var tint: Color {
        switch gauge?.tint ?? .accent {
        case .accent: return PeekTheme.accent
        case .amber: return PeekTheme.amber
        case .red: return PeekTheme.red
        }
    }

    private var title: String { info.name.replacingOccurrences(of: "Peek", with: "") }

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                RingGauge(fraction: gauge?.fraction ?? 0, color: tint, lineWidth: 7) {
                    Text(gauge?.value ?? "–").font(.system(size: 15, weight: .semibold)).monospacedDigit()
                }
                .frame(width: 70, height: 70)
                Text(title).font(.system(size: 14, weight: .medium))
                Text(gauge?.caption ?? " ")
                    .font(.system(size: 11.5, design: .monospaced))
                    .foregroundStyle(PeekTheme.muted)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity)
            .themedCard(radius: 14, padding: 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(TileButtonStyle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(info.name), \(gauge.map { "\($0.value), \($0.caption)" } ?? "reading")")
        .accessibilityAddTraits(.isButton)
    }
}

/// A category of utilities as a card of rows: icon, name, launcher summary (or tagline) and a chevron.
private struct UtilitySection: View {
    @EnvironmentObject private var registry: UtilityRegistry
    @EnvironmentObject private var router: UtilityRouter
    let title: String
    let items: [UtilityInfo]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionLabel(text: title)
            VStack(spacing: 0) {
                ForEach(Array(items.enumerated()), id: \.element.id) { index, info in
                    if index > 0 { Rectangle().fill(PeekTheme.hairline).frame(height: 1).padding(.leading, 54) }
                    PeekRow(icon: info.icon, title: info.name,
                            subtitle: registry.summaries[info.id] ?? info.tagline) { router.go(.utility(info.id)) }
                        .help(info.question)
                }
            }
            .padding(.vertical, 2)
            .background(PeekTheme.card, in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(PeekTheme.border))
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }
}

private struct TileButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.75 : 1)
            .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
    }
}
#endif
