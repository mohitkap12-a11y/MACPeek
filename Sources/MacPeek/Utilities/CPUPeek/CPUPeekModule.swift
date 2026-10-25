#if os(macOS)
import SwiftUI
import MacPeekCore

/// CPUPeek as a MacPeek utility: read-only. Samples only while its screen is visible; the launcher ring is two CPU
/// readings half a second apart, plus the load average and thermal state.
@MainActor
final class CPUPeekModule: UtilityModule {
    let info = UtilityCatalog.cpuPeek
    private let store: CPUStore

    init(store: CPUStore) {
        self.store = store
    }

    var gaugeOrder: Int? { 0 }
    func launcherGauge() async -> LauncherGauge? { await store.launcherGauge() }
    func didAppear() { store.startSampling() }
    func didDisappear() { store.stopSampling() }

    func makeView() -> AnyView {
        AnyView(CPUPeekView().environmentObject(store))
    }
}
#endif
