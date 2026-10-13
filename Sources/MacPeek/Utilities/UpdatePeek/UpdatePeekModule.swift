#if os(macOS)
import SwiftUI
import MacPeekCore

/// UpdatePeek as a MacPeek utility. The launcher summary is the local macOS version; nothing runs until the user presses Check.
@MainActor
final class UpdatePeekModule: UtilityModule {
    let info = UtilityCatalog.updatePeek
    private let store: UpdateStore

    init(store: UpdateStore) {
        self.store = store
    }

    func launcherSummary() async -> String? { store.launcherSummary }

    func didAppear() { store.reload() }
    func didDisappear() { store.cancel() }

    func makeView() -> AnyView {
        AnyView(UpdatePeekView().environmentObject(store))
    }
}
#endif
