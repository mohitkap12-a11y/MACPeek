#if os(macOS)
import SwiftUI

extension View {
    /// Rounded, subtly bordered container used for grouped content.
    func peekCard() -> some View {
        padding(12)
            .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.primary.opacity(0.08)))
    }
}
#endif
