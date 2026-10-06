#if os(macOS)
import SwiftUI
import MacPeekCore

/// EnvPeek as a MacPeek utility. Reads only when you ask (or open the screen), keeps nothing in the background.
@MainActor
final class EnvPeekModule: UtilityModule {
    let info = UtilityCatalog.envPeek
    private let store: EnvStore

    init(store: EnvStore) {
        self.store = store
    }

    func didAppear() { store.enter() }
    func didDisappear() { store.leave() }

    func makeView() -> AnyView {
        AnyView(EnvPeekView().environmentObject(store))
    }
}
#endif
