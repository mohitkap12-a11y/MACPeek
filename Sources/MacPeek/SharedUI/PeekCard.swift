#if os(macOS)
import SwiftUI

extension View {
    /// Rounded, subtly bordered container used for grouped content.
    func peekCard() -> some View {
        themedCard(radius: 12, padding: 12)
    }
}
#endif
