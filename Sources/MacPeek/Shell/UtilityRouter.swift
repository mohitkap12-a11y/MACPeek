#if os(macOS)
import Foundation

enum Route: Equatable {
    case launcher
    case utility(String)
    case manage
    case settings
    case about
    case support
}

/// Navigation inside the single compact popover. It also drives utility lifecycle, so a utility
/// refreshes only while its screen is visible.
@MainActor
final class UtilityRouter: ObservableObject {
    @Published private(set) var route: Route = .launcher
    private let registry: UtilityRegistry
    /// Where Support was opened from, so its Back button returns there (launcher or About).
    private var supportOrigin: Route = .launcher

    init(registry: UtilityRegistry) {
        self.registry = registry
    }

    func go(_ new: Route) {
        guard new != route else { return }
        if new == .support { supportOrigin = route }
        leave(route)
        route = new
        enter(new)
    }

    func back() { go(.launcher) }

    /// Back from Support: return to the screen that opened it.
    func backFromSupport() { go(supportOrigin) }

    func popoverWillShow() {
        registry.refreshSummaries()
    }

    /// Always return to the launcher so the next open is predictable, and stop any live work.
    func popoverDidClose() {
        registry.cancelSummaries()
        leave(route)
        route = .launcher
        supportOrigin = .launcher
    }

    private func enter(_ route: Route) {
        if case .utility(let id) = route { registry.module(for: id)?.didAppear() }
    }

    private func leave(_ route: Route) {
        if case .utility(let id) = route { registry.anyModule(for: id)?.didDisappear() }
    }
}
#endif
