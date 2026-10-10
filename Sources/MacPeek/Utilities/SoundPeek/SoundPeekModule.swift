#if os(macOS)
import SwiftUI
import MacPeekCore

/// SoundPeek as a MacPeek utility. Change listeners run only while its screen is visible; the launcher summary is one read.
@MainActor
final class SoundPeekModule: UtilityModule {
    let info = UtilityCatalog.soundPeek
    private let store: SoundStore

    init(store: SoundStore) {
        self.store = store
    }

    func launcherSummary() async -> String? {
        await store.readOnce()
        guard !Task.isCancelled, store.error == nil, let name = store.snapshot?.defaultDevice(.output)?.name else { return nil }
        return "Output: \(name)"
    }

    func didAppear() { store.start() }
    func didDisappear() { store.stop() }

    func makeView() -> AnyView {
        AnyView(SoundPeekView().environmentObject(store))
    }
}
#endif
