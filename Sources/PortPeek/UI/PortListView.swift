#if os(macOS)
import SwiftUI
import PortPeekCore

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

    @ViewBuilder private var emptyState: some View {
        VStack(spacing: 6) {
            Image(systemName: store.query.isEmpty ? "network.slash" : "magnifyingglass")
                .font(.system(size: 28)).foregroundStyle(.tertiary)
            Text(store.query.isEmpty ? "No listening ports" : "No matches for “\(store.query)”")
                .font(.callout).foregroundStyle(.secondary)
            if store.query.isEmpty {
                Text("PortPeek lists ports opened by your user account.")
                    .font(.caption).foregroundStyle(.tertiary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
#endif
