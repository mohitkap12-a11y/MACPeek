#if os(macOS)
import SwiftUI
import MacPeekCore

/// NetPeek as a MacPeek utility. One cheap read for the launcher summary; refreshes only while its screen is visible;
/// pings only when you press "Run checks".
@MainActor
final class NetPeekModule: UtilityModule {
    let info = UtilityCatalog.netPeek
    private let store: NetStore

    init(store: NetStore) {
        self.store = store
    }

    func launcherSummary() async -> String? {
        await store.refresh()
        guard !Task.isCancelled, store.error == nil, let snapshot = store.snapshot else { return nil }
        return snapshot.primary?.displayName ?? "Offline"
    }

    func didAppear() { store.startPolling() }
    func didDisappear() { store.stopPolling() }

    func makeView() -> AnyView {
        AnyView(NetPeekView().environmentObject(store))
    }
}
#endif
