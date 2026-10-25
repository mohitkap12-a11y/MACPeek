#if os(macOS)
import SwiftUI
import AppKit

/// MacPeek's colours, one value for light and one for dark appearance. The popover follows the appearance chosen in
/// Settings or with the launcher's sun/moon button.
enum PeekTheme {
    static let ground = Color(light: 0xF7F7F8, dark: 0x0E0E10)
    static let card = Color(light: 0xFFFFFF, dark: 0x17171A)
    static let border = Color(light: 0xE3E3E8, dark: 0x2A2A2F)
    static let hairline = Color(light: 0xECECF0, dark: 0x202024)
    static let track = Color(light: 0xEBEBEF, dark: 0x2C2C31)
    /// Secondary text with at least 4.5:1 contrast on `card` and `ground` in both appearances.
    static let muted = Color(light: 0x5F5F68, dark: 0xA1A1AA)

    static let accent = Color(light: 0x4F5BD5, dark: 0x8EA0FF)
    static let amber = Color(light: 0xA3611F, dark: 0xE3AC43)
    static let red = Color(light: 0xD4483A, dark: 0xFF7A6B)
    static let green = Color(light: 0x1F8A55, dark: 0x4FC28A)
    static let teal = Color(light: 0x1F8A83, dark: 0x4CB5AE)
    static let freeSegment = Color(light: 0xD6D6DC, dark: 0x3A3A41)
    static let pillBackground = Color(light: 0xECEBFD, dark: 0x262145)
    static let pillText = Color(light: 0x4A3FC4, dark: 0xB3A8FF)
    static let noteBackground = Color(light: 0xFDF6E7, dark: 0x221C10)
    static let noteBorder = Color(light: 0xF0DCB0, dark: 0x4A3A17)
    static let warningText = Color(light: 0x8A5410, dark: 0xF0BD5C)
}

extension Color {
    /// A colour that resolves to `light` or `dark` with the view's appearance. Values are 0xRRGGBB.
    init(light: UInt32, dark: UInt32) {
        self.init(nsColor: NSColor(name: nil) { appearance in
            let hex = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
            return NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
                           blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
        })
    }
}

extension View {
    /// The card style of the launcher and the CPU, Memory and Disk screens.
    func themedCard(radius: CGFloat = 12, padding: CGFloat = 12) -> some View {
        self.padding(padding)
            .background(PeekTheme.card, in: RoundedRectangle(cornerRadius: radius))
            .overlay(RoundedRectangle(cornerRadius: radius).strokeBorder(PeekTheme.border))
    }
}

/// A small upper-case section label ("DETAILS", "TOP PROCESSES").
struct SectionLabel: View {
    let text: String
    var trailing: String? = nil

    var body: some View {
        HStack {
            Text(text.uppercased())
            Spacer(minLength: 4)
            if let trailing { Text(trailing.uppercased()) }
        }
        .font(.system(size: 10.5, weight: .semibold))
        .tracking(0.6)
        .foregroundStyle(PeekTheme.muted)
        .accessibilityAddTraits(.isHeader)
    }
}

/// The "Sampled" capsule shown on screens whose values are measured over an interval.
struct SampledPill: View {
    var text = "Sampled"

    var body: some View {
        Text(text)
            .font(.system(size: 10.5, weight: .semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .foregroundStyle(PeekTheme.pillText)
            .background(PeekTheme.pillBackground, in: Capsule())
    }
}

/// A coloured square used as a legend key.
struct LegendDot: View {
    let color: Color
    var size: CGFloat = 8

    var body: some View {
        RoundedRectangle(cornerRadius: 2).fill(color).frame(width: size, height: size).accessibilityHidden(true)
    }
}

/// A label / value row with an optional legend key, as in the Details sections.
struct DetailRow: View {
    let label: String
    let value: String
    var dot: Color? = nil

    var body: some View {
        HStack(spacing: 8) {
            if let dot { LegendDot(color: dot) } else { Color.clear.frame(width: 8, height: 8) }
            Text(label).foregroundStyle(PeekTheme.muted)
            Spacer(minLength: 4)
            Text(value).font(.system(size: 12.5, design: .monospaced)).textSelection(.enabled)
        }
        .font(.system(size: 13))
        .accessibilityElement(children: .combine)
    }
}
#endif
