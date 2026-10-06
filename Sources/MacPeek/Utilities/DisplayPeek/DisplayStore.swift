#if os(macOS)
import Foundation
import DisplayPeekKit

/// Observable state for DisplayPeek. Reads display information when the screen opens or the user asks;
/// nothing runs in the background and an in-flight read is cancelled when the screen is left.
@MainActor
final class DisplayStore: ObservableObject {
    @Published private(set) var report: DisplayReport?
    @Published private(set) var isLoading = false
    @Published private(set) var error: String?

    private let discovery: DisplayDiscovering
    private var task: Task<Void, Never>?

    init(discovery: DisplayDiscovering) {
        self.discovery = discovery
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

    private func load() async {
        isLoading = true
        defer { if !Task.isCancelled { isLoading = false } }
        do {
            let result = try await discovery.report()
            guard !Task.isCancelled else { return }
            report = result
            error = nil
        } catch {
            if Task.isCancelled { return }
            self.error = error.localizedDescription
            Log.displayPeek.error("read failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}
#endif
