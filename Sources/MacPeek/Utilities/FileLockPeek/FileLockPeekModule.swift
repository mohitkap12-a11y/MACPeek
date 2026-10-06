#if os(macOS)
import SwiftUI
import MacPeekCore
import FileLockPeekKit

/// FileLockPeek as a MacPeek utility. It never scans in the background: only when you pick a path and ask.
@MainActor
final class FileLockPeekModule: UtilityModule {
    let info = UtilityCatalog.fileLockPeek
    private let store: FileLockStore

    init(store: FileLockStore) {
        self.store = store
    }

    // No launcher summary: there is nothing to show until the user chooses a path, and nothing to scan.
    func didDisappear() { store.cancel() }

    func makeView() -> AnyView {
        AnyView(FileLockPeekView().environmentObject(store))
    }
}
#endif
