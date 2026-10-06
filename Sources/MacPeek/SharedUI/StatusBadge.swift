#if os(macOS)
import SwiftUI

struct StatusBadge: View {
    enum Tone { case neutral, good, warning, info }
    let text: String
    var tone: Tone = .neutral

    private var color: Color {
        switch tone {
        case .neutral: return .secondary
        case .good: return .green
        case .warning: return .orange
        case .info: return .accentColor
        }
    }

    var body: some View {
        Text(text)
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.14), in: Capsule())
    }
}
#endif
