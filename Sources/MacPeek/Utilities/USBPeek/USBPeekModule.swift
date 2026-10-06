#if os(macOS)
import SwiftUI
import MacPeekCore

/// USBPeek as a MacPeek utility. Reads only while its screen is open: no launcher summary, no polling.
@MainActor
final class USBPeekModule: UtilityModule {
    let info = UtilityCatalog.usbPeek
    private let store: USBStore

    init(store: USBStore) {
        self.store = store
    }

    func didAppear() { store.refresh() }
    func didDisappear() { store.cancel() }

    func makeView() -> AnyView {
        AnyView(USBPeekView().environmentObject(store))
    }
}
#endif
