#if os(macOS)
import SwiftUI
import MacPeekCore

/// CPUPeek as a MacPeek utility: read-only. Samples only while its screen is visible; the launcher line is one cheap
/// read of the load average and thermal state.
@MainActor
final class CPUPeekModule: UtilityModule {
    let info = UtilityCatalog.cpuPeek
    private let store: CPUStore

    init(store: CPUStore) {
        self.store = store
    }

    func launcherSummary() async -> String? { await store.launcherSummary() }
    func didAppear() { store.startSampling() }
    func didDisappear() { store.stopSampling() }

    func makeView() -> AnyView {
        AnyView(CPUPeekView().environmentObject(store))
    }
}
#endif
