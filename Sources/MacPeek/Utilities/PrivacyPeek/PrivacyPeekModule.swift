#if os(macOS)
import SwiftUI
import MacPeekCore

/// PrivacyPeek as a MacPeek utility: static, informational content. It has no store, reads nothing from the Mac and
/// holds no state beyond which explanation is open.
@MainActor
final class PrivacyPeekModule: UtilityModule {
    let info = UtilityCatalog.privacyPeek

    func makeView() -> AnyView {
        AnyView(PrivacyPeekView())
    }
}
#endif
