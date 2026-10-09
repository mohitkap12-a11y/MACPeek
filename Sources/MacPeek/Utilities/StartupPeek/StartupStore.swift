#if os(macOS)
import Foundation
import StartupPeekKit

/// Observable state for StartupPeek. It reads when the screen opens or the user asks, never in the background, and a read
/// in flight is cancelled when the screen is left. Nothing here changes any startup item.
@MainActor
final class StartupStore: ObservableObject {
    @Published private(set) var inventory: StartupInventory?
    @Published private(set) var isLoading = false
    @Published private(set) var error: String?
    @Published var query = ""

    private let service: StartupInventoryProviding
    private var task: Task<Void, Never>?

    init(service: StartupInventoryProviding) {
        self.service = service
    }

    var filteredItems: [StartupItem] {
        StartupSearch.filter(inventory?.items ?? [], query: query)
    }

    func refresh() {
        task?.cancel()
        task = Task { [weak self] in await self?.load() }
    }

    func cancel() {
        task?.cancel()
        task = nil
        isLoading = false
    }

    /// One-off count for the launcher summary.
    func summaryCount() async -> Int? {
        guard let result = try? await service.inventory(), !Task.isCancelled else { return nil }
        return result.items.count
    }

    private func load() async {
        isLoading = true
        defer { if !Task.isCancelled { isLoading = false } }
        do {
            let result = try await service.inventory()
            guard !Task.isCancelled else { return }
            inventory = result
            error = nil
        } catch {
            if Task.isCancelled { return }
            self.error = error.localizedDescription
            Log.startupPeek.error("inventory failed")
        }
    }
}
#endif
