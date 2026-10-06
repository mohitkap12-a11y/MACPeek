#if os(macOS)
import SwiftUI

/// A tappable launcher row: icon tile, title, one-line subtitle, chevron.
struct PeekRow: View {
    let icon: String
    let title: String
    let subtitle: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                IconTile(symbol: icon)
                VStack(alignment: .leading, spacing: 1) {
                    Text(title).font(.system(size: 13, weight: .medium))
                    Text(subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer(minLength: 4)
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(PeekRowButtonStyle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title), \(subtitle)")
        .accessibilityAddTraits(.isButton)
    }
}

struct PeekRowButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        HoverBackground(pressed: configuration.isPressed) { configuration.label }
    }
}

private struct HoverBackground<Content: View>: View {
    let pressed: Bool
    @ViewBuilder let content: () -> Content
    @State private var hovering = false

    var body: some View {
        content()
            .background(pressed ? Color.primary.opacity(0.10) : hovering ? Color.primary.opacity(0.05) : .clear)
            .onHover { hovering = $0 }
    }
}

struct IconTile: View {
    let symbol: String
    var size: CGFloat = 30

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: size * 0.5, weight: .medium))
            .foregroundStyle(Color.accentColor)
            .frame(width: size, height: size)
            .background(Color.accentColor.opacity(0.14), in: RoundedRectangle(cornerRadius: size * 0.28))
            .accessibilityHidden(true)
    }
}
#endif
