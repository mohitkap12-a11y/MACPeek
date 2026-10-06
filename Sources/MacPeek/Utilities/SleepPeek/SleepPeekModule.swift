#if os(macOS)
import SwiftUI
import MacPeekCore

/// SleepPeek as a MacPeek utility: read-only. Polls the cheap assertion list only while its screen is visible.
@MainActor
final class SleepPeekModule: UtilityModule {
    let info = UtilityCatalog.sleepPeek
    private let store: SleepStore

    init(store: SleepStore) {
        self.store = store
    }

    func launcherSummary() async -> String? {
        await store.refresh()
        guard !Task.isCancelled, store.error == nil, let diagnosis = store.snapshot?.diagnosis else { return nil }
        if diagnosis.systemSleepBlocked {
            let n = diagnosis.blockers.filter { $0.assertion.preventsSystemSleep }.count
            return n == 1 ? "1 blocker" : "\(n) blockers"
        }
        if diagnosis.displaySleepBlocked { return "Display held awake" }
        return diagnosis.expectedHolds.isEmpty ? "No blockers" : "Display is on"
    }

    func didAppear() { store.startPolling() }
    func didDisappear() { store.stopPolling() }

    func makeView() -> AnyView {
        AnyView(SleepPeekView().environmentObject(store))
    }
}
#endif
