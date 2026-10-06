#if os(macOS)
import SwiftUI
import MacPeekCore

/// DNSPeek as a MacPeek utility: read-only. One cheap `scutil --dns` read for the launcher summary; lookups only on request.
@MainActor
final class DNSPeekModule: UtilityModule {
    let info = UtilityCatalog.dnsPeek
    private let store: DNSStore

    init(store: DNSStore) {
        self.store = store
    }

    func launcherSummary() async -> String? { await store.summary() }
    func didAppear() { store.refresh() }
    func didDisappear() { store.cancel() }

    func makeView() -> AnyView {
        AnyView(DNSPeekView().environmentObject(store))
    }
}
#endif
