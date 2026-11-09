#if os(macOS)
import SwiftUI
import MacPeekCore

/// ContainerPeek as a MacPeek utility. Reads only while its screen is visible; actions run only after the person
/// confirms and the container has been re-checked.
@MainActor
final class ContainerPeekModule: UtilityModule {
    let info = UtilityCatalog.containerPeek
    private let store: ContainerStore

    init(store: ContainerStore) {
        self.store = store
    }

    func launcherSummary() async -> String? {
        await store.launcherSummary()
    }

    func didAppear() { store.startPolling() }
    func didDisappear() { store.stopPolling() }

    func makeView() -> AnyView {
        AnyView(ContainerPeekView().environmentObject(store))
    }
}
#endif
