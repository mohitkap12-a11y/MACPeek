#if os(macOS)
import Foundation

enum Route: Equatable {
    case launcher
    case utility(String)
    case manage
    case settings
    case remote
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
        if route == .launcher { registry.startGaugeUpdates() }
    }

    /// Always return to the launcher so the next open is predictable, and stop any live work.
    func popoverDidClose() {
        registry.cancelSummaries()
        registry.stopGaugeUpdates()
        leave(route)
        route = .launcher
        supportOrigin = .launcher
    }

    private func enter(_ route: Route) {
        switch route {
        case .utility(let id): registry.module(for: id)?.didAppear()
        case .launcher:
            // Back on the launcher: fresh ring readings now, then live updates while it stays on screen.
            registry.startGaugeUpdates(immediately: true)
        default: break
        }
    }

    private func leave(_ route: Route) {
        switch route {
        case .utility(let id): registry.anyModule(for: id)?.didDisappear()
        case .launcher: registry.stopGaugeUpdates()
        default: break
        }
    }
}
#endif
