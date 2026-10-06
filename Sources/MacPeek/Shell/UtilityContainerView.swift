#if os(macOS)
import SwiftUI

/// Hosts one utility's view under a standard header with a back button.
struct UtilityContainerView: View {
    let id: String
    @EnvironmentObject private var registry: UtilityRegistry
    @EnvironmentObject private var router: UtilityRouter

    var body: some View {
        if let module = registry.module(for: id) {
            VStack(spacing: 0) {
                PeekHeader(title: module.info.name, subtitle: module.info.tagline, onBack: { router.back() })
                Divider()
                module.makeView().frame(maxHeight: .infinity)
            }
        } else {
            VStack(spacing: 0) {
                PeekHeader(title: "Utility unavailable", onBack: { router.back() })
                Divider()
                EmptyState(symbol: "questionmark.square.dashed", title: "This utility is turned off",
                           message: "Enable it from Manage utilities.")
            }
        }
    }
}
#endif
