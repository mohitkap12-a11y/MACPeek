#if os(macOS)
import SwiftUI
import MacPeekCore

/// GPUPeek as a MacPeek utility: read-only. Samples only while its screen is visible.
@MainActor
final class GPUPeekModule: UtilityModule {
    let info = UtilityCatalog.gpuPeek
    private let store: GPUStore

    init(store: GPUStore) {
        self.store = store
    }

    func launcherSummary() async -> String? {
        await store.sample()
        guard !Task.isCancelled, store.error == nil else { return nil }
        return store.snapshot?.summary
    }

    func didAppear() { store.startSampling() }
    func didDisappear() { store.stopSampling() }

    func makeView() -> AnyView {
        AnyView(GPUPeekView().environmentObject(store))
    }
}
#endif
