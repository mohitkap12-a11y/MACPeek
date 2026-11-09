#if os(macOS)
import SwiftUI
import MacPeekCore

/// GPUPeek as a MacPeek utility: read-only. Samples only while its screen is visible; the launcher ring (second, after
/// CPU) is one `ioreg` read, repeated only while the launcher is on screen.
@MainActor
final class GPUPeekModule: UtilityModule {
    let info = UtilityCatalog.gpuPeek
    private let store: GPUStore

    init(store: GPUStore) {
        self.store = store
    }

    var gaugeOrder: Int? { 1 }
    func launcherGauge() async -> LauncherGauge? { await store.launcherGauge() }

    func didAppear() { store.startSampling() }
    func didDisappear() { store.stopSampling() }

    func makeView() -> AnyView {
        AnyView(GPUPeekView().environmentObject(store))
    }
}
#endif
