#if os(macOS)
import SwiftUI
import MacPeekCore

/// USBPeek as a MacPeek utility. Reads only while its screen is open (and re-reads periodically then): no launcher summary, nothing in the background.
@MainActor
final class USBPeekModule: UtilityModule {
    let info = UtilityCatalog.usbPeek
    private let store: USBStore

    init(store: USBStore) {
        self.store = store
    }

    func didAppear() { store.startPolling() }
    func didDisappear() { store.cancel() }

    func makeView() -> AnyView {
        AnyView(USBPeekView().environmentObject(store))
    }
}
#endif
