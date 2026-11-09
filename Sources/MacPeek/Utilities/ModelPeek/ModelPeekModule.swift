#if os(macOS)
import SwiftUI
import MacPeekCore

/// ModelPeek as a MacPeek utility: read-only. Reads only while its screen is visible.
@MainActor
final class ModelPeekModule: UtilityModule {
    let info = UtilityCatalog.modelPeek
    private let store: ModelStore

    init(store: ModelStore) {
        self.store = store
    }

    func launcherSummary() async -> String? {
        await store.refreshOnce()
        guard !Task.isCancelled, store.error == nil else { return nil }
        return store.snapshot?.summary
    }

    func didAppear() { store.startPolling() }
    func didDisappear() { store.stopPolling() }

    func makeView() -> AnyView {
        AnyView(ModelPeekView().environmentObject(store))
    }
}
#endif
