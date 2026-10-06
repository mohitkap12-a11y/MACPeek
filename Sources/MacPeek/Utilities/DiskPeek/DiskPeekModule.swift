#if os(macOS)
import SwiftUI
import MacPeekCore

/// DiskPeek as a MacPeek utility. It samples only while its screen is visible and has no launcher summary.
@MainActor
final class DiskPeekModule: UtilityModule {
    let info = UtilityCatalog.diskPeek
    private let store: DiskStore

    init(store: DiskStore) {
        self.store = store
    }

    func didAppear() { store.startSampling() }
    func didDisappear() { store.stopSampling() }

    func makeView() -> AnyView {
        AnyView(DiskPeekView().environmentObject(store))
    }
}
#endif
