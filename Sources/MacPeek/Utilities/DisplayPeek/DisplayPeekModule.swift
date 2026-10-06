#if os(macOS)
import SwiftUI
import MacPeekCore

/// DisplayPeek as a MacPeek utility. Reads only while its screen is open: no launcher summary, no polling.
@MainActor
final class DisplayPeekModule: UtilityModule {
    let info = UtilityCatalog.displayPeek
    private let store: DisplayStore

    init(store: DisplayStore) {
        self.store = store
    }

    func didAppear() { store.refresh() }
    func didDisappear() { store.cancel() }

    func makeView() -> AnyView {
        AnyView(DisplayPeekView().environmentObject(store))
    }
}
#endif
