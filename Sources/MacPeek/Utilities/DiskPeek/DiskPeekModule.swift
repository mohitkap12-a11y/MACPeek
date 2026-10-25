#if os(macOS)
import SwiftUI
import MacPeekCore

/// DiskPeek as a MacPeek utility. It samples only while its screen is visible; the launcher ring is one
/// read of the startup disk's capacity.
@MainActor
final class DiskPeekModule: UtilityModule {
    let info = UtilityCatalog.diskPeek
    private let store: DiskStore

    init(store: DiskStore) {
        self.store = store
    }

    var gaugeOrder: Int? { 2 }
    func launcherGauge() async -> LauncherGauge? { await store.launcherGauge() }
    func didAppear() { store.startSampling() }
    func didDisappear() { store.stopSampling() }

    func makeView() -> AnyView {
        AnyView(DiskPeekView().environmentObject(store))
    }
}
#endif
