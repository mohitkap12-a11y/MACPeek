#if os(macOS)
import SwiftUI
import MacPeekCore

/// MemoryPeek as a MacPeek utility: read-only. Reads memory only while its screen is visible; the launcher ring is
/// one cheap read of memory use and pressure.
@MainActor
final class MemoryPeekModule: UtilityModule {
    let info = UtilityCatalog.memoryPeek
    private let store: MemoryStore

    init(store: MemoryStore) {
        self.store = store
    }

    var gaugeOrder: Int? { 1 }
    func launcherGauge() async -> LauncherGauge? { await store.launcherGauge() }
    func didAppear() { store.startPolling() }
    func didDisappear() { store.stopPolling() }

    func makeView() -> AnyView {
        AnyView(MemoryPeekView().environmentObject(store))
    }
}
#endif
