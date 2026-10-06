#if os(macOS)
import Foundation

enum Route: Equatable {
    case launcher
    case utility(String)
    case manage
    case settings
    case about
}

/// Navigation inside the single compact popover. It also drives utility lifecycle, so a utility
/// refreshes only while its screen is visible.
@MainActor
final class UtilityRouter: ObservableObject {
    @Published private(set) var route: Route = .launcher
    private let registry: UtilityRegistry

    init(registry: UtilityRegistry) {
        self.registry = registry
    }

    func go(_ new: Route) {
        guard new != route else { return }
        leave(route)
        route = new
        enter(new)
    }

    func back() { go(.launcher) }

    func popoverWillShow() {
        Task { await registry.refreshSummaries() }
    }

    /// Always return to the launcher so the next open is predictable, and stop any live work.
    func popoverDidClose() {
        leave(route)
        route = .launcher
    }

    private func enter(_ route: Route) {
        if case .utility(let id) = route { registry.module(for: id)?.didAppear() }
    }

    private func leave(_ route: Route) {
        if case .utility(let id) = route { registry.anyModule(for: id)?.didDisappear() }
    }
}
#endif
