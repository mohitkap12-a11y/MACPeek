#if os(macOS)
import SwiftUI
import MacPeekCore

/// The main screen: ring tiles for CPU, Memory and Disk, then a tile for every other enabled utility. Each tile
/// opens its utility; the values are the one-shot readings taken when the popover opened.
struct LauncherView: View {
    @EnvironmentObject private var registry: UtilityRegistry
    @EnvironmentObject private var router: UtilityRouter
    @EnvironmentObject private var settings: AppSettings
    @Environment(\.colorScheme) private var colorScheme

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 3)

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
                        LazyVGrid(columns: columns, spacing: 8) {
                            ForEach(registry.tileUtilities) { info in
                                UtilityTile(info: info, summary: registry.summaries[info.id]) { router.go(.utility(info.id)) }
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

/// Every other utility: its name and, when it has one, its launcher summary.
private struct UtilityTile: View {
    let info: UtilityInfo
    let summary: String?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 5) {
                    Image(systemName: info.icon)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(PeekTheme.accent)
                        .accessibilityHidden(true)
                    Text(info.name)
                        .font(.system(size: 12.5, weight: .medium))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                Text(summary ?? " ")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(PeekTheme.muted)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, minHeight: 32, alignment: .leading)
            .themedCard(radius: 11, padding: 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(TileButtonStyle())
        .help(info.question)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(summary.map { "\(info.name), \($0)" } ?? info.name)
        .accessibilityHint(info.question)
        .accessibilityAddTraits(.isButton)
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
