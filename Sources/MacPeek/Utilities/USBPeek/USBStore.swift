#if os(macOS)
import Foundation
import USBPeekKit

/// Observable state for USBPeek. Reads when the screen opens or the user asks (no polling), and cancels an
/// in-flight read when the screen is left.
@MainActor
final class USBStore: ObservableObject {
    @Published private(set) var snapshot: USBSnapshot?
    @Published private(set) var isLoading = false
    @Published private(set) var error: String?
    @Published var selectedID: String?

    private let discovery: USBDiscovering
    private var task: Task<Void, Never>?

    init(discovery: USBDiscovering) {
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
            let result = try await discovery.snapshot()
            guard !Task.isCancelled else { return }
            snapshot = result
            error = nil
            if let id = selectedID, !result.allDevices.contains(where: { $0.id == id }) { selectedID = nil }
        } catch {
            if Task.isCancelled { return }
            self.error = error.localizedDescription
            Log.usbPeek.error("read failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}
#endif
