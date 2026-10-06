#if os(macOS)
import SwiftUI
import MacPeekCore
import PortPeekKit

/// PortPeek as a MacPeek utility. Polls only while its screen is visible.
@MainActor
final class PortPeekModule: UtilityModule {
    let info = UtilityCatalog.portPeek
    private let store: PortStore

    init(store: PortStore) {
        self.store = store
    }

    func launcherSummary() async -> String? {
        await store.refresh()
        guard store.scanError == nil else { return nil }
        let n = store.ports.count
        return n == 1 ? "1 active" : "\(n) active"
    }

    func didAppear() { store.startPolling() }
    func didDisappear() { store.stopPolling() }

    func makeView() -> AnyView {
        AnyView(PortPeekView().environmentObject(store))
    }
}
#endif
