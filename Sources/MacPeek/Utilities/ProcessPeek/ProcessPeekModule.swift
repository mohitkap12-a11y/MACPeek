#if os(macOS)
import SwiftUI
import MacPeekCore

/// ProcessPeek as a MacPeek utility. Reads only while its screen is open: no launcher summary, no polling.
@MainActor
final class ProcessPeekModule: UtilityModule {
    let info = UtilityCatalog.processPeek
    private let store: ProcessStore

    init(store: ProcessStore) {
        self.store = store
    }

    func didAppear() { store.refresh() }
    func didDisappear() { store.cancel() }

    func makeView() -> AnyView {
        AnyView(ProcessPeekView().environmentObject(store))
    }
}
#endif
