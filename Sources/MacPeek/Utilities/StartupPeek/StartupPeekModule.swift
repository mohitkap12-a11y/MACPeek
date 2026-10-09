#if os(macOS)
import SwiftUI
import MacPeekCore

/// StartupPeek as a MacPeek utility: a read-only inventory, read only while its screen is open.
@MainActor
final class StartupPeekModule: UtilityModule {
    let info = UtilityCatalog.startupPeek
    private let store: StartupStore

    init(store: StartupStore) {
        self.store = store
    }

    func didAppear() { store.refresh() }
    func didDisappear() { store.cancel() }

    func makeView() -> AnyView {
        AnyView(StartupPeekView().environmentObject(store))
    }
}
#endif
