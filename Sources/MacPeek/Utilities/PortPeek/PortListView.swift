#if os(macOS)
import SwiftUI
import MacPeekCore
import PortPeekKit

struct PortListView: View {
    @EnvironmentObject private var store: PortStore

    var body: some View {
        let items = store.filteredPorts
        Group {
            if items.isEmpty {
                emptyState
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        // Lazy so hundreds of rows stay cheap.
                        LazyVStack(spacing: 0) {
                            ForEach(items) { port in
                                PortRowView(port: port)
                                Divider().opacity(0.4)
                            }
                        }
                    }
                    .focusable()
                    .onMoveCommand { direction in move(direction, in: items, proxy: proxy) }
                }
            }
        }
        .frame(maxHeight: .infinity)
    }

    private func move(_ direction: MoveCommandDirection, in items: [PortInfo], proxy: ScrollViewProxy) {
        guard !items.isEmpty else { return }
        let current = items.firstIndex { $0.id == store.selectedID }
        let next: Int
        switch direction {
        case .down: next = min((current ?? -1) + 1, items.count - 1)
        case .up: next = max((current ?? items.count) - 1, 0)
        default: return
        }
        store.selectedID = items[next].id
        proxy.scrollTo(items[next].id)
    }

    private var emptyState: some View {
        EmptyState(
            symbol: store.query.isEmpty ? "network.slash" : "magnifyingglass",
            title: store.query.isEmpty ? "No listening ports" : "No matches for “\(store.query)”",
            message: store.query.isEmpty ? "PortPeek lists ports opened by your user account." : nil
        )
    }
}
#endif
