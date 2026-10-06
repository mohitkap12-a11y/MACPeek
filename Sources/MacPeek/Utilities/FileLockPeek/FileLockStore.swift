#if os(macOS)
import Foundation
import MacPeekCore
import FileLockPeekKit

/// Observable state for FileLockPeek. Scans only when asked (no polling: folder scans are recursive), and
/// cancels any in-flight scan when the screen is left. Owns the kill flow; contains no AppKit.
@MainActor
final class FileLockStore: ObservableObject {
    @Published var pathText = ""
    /// The path of the last scan (what the results and kill actions refer to).
    @Published private(set) var scannedPath: String?
    @Published private(set) var holders: [FileLockHolder] = []
    @Published private(set) var isScanning = false
    @Published private(set) var scanError: String?
    @Published var selectedID: FileLockHolder.ID?
    @Published private(set) var killingID: FileLockHolder.ID?
    /// Set when SIGTERM did not stop the process: the UI then offers an explicit force-kill.
    @Published private(set) var forceCandidate: FileLockHolder?
    @Published private(set) var banner: Banner?

    private let service: FileLockService
    private let terminator: FileLockTerminator
    private let permissions: PermissionService
    private let settings: AppSettings
    private let notifier: NotificationService
    private var scanTask: Task<Void, Never>?
    private var bannerTask: Task<Void, Never>?

    init(service: FileLockService, terminator: FileLockTerminator, permissions: PermissionService,
         settings: AppSettings, notifier: NotificationService) {
        self.service = service
        self.terminator = terminator
        self.permissions = permissions
        self.settings = settings
        self.notifier = notifier
    }

    var hasScanned: Bool { scannedPath != nil || scanError != nil }

    func capability(for holder: FileLockHolder) -> TerminationCapability { permissions.capability(for: holder) }

    // MARK: Scanning

    /// Scans the path in `pathText` (or `path`, which replaces it).
    func scan(path: String? = nil) {
        if let path { pathText = path }
        let cleaned = Self.clean(pathText)
        guard !cleaned.isEmpty else { return }
        scanTask?.cancel()
        scanTask = Task { [weak self] in await self?.performScan(cleaned) }
    }

    func rescan() { scan() }

    /// Called when the screen is left: stop any running lsof.
    func cancel() {
        scanTask?.cancel()
        scanTask = nil
        isScanning = false
    }

    private func performScan(_ path: String) async {
        isScanning = true
        defer { if !Task.isCancelled { isScanning = false } }
        do {
            let result = try await service.holders(of: path)
            guard !Task.isCancelled else { return }
            holders = result
            scannedPath = path
            scanError = nil
            if let id = selectedID, !result.contains(where: { $0.id == id }) { selectedID = nil }
            // A force-kill offer is only valid for the exact process that ignored SIGTERM.
            if let candidate = forceCandidate, !result.contains(where: { Self.isSameProcess($0, candidate) }) {
                forceCandidate = nil
            }
        } catch {
            // A cancelled scan (screen left, new scan started) is not an error to show.
            if Task.isCancelled { return }
            holders = []
            scannedPath = nil
            scanError = error.localizedDescription
            Log.fileLockPeek.error("scan failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Trims whitespace and surrounding quotes, and expands a leading `~`.
    static func clean(_ text: String) -> String {
        var s = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.count >= 2, (s.hasPrefix("\"") && s.hasSuffix("\"")) || (s.hasPrefix("'") && s.hasSuffix("'")) {
            s = String(s.dropFirst().dropLast())
        }
        return (s as NSString).expandingTildeInPath
    }

    // MARK: Termination

    func terminate(_ holder: FileLockHolder) async { await run(holder, force: false) }
    func dismissForce() { forceCandidate = nil }

    /// Force-kills the *original* candidate (never a refreshed row that merely shares its PID);
    /// the termination service revalidates it again, including start time, before sending SIGKILL.
    func confirmForceTerminate() async {
        guard let candidate = forceCandidate else { return }
        await run(candidate, force: true)
    }

    private static func isSameProcess(_ a: FileLockHolder, _ b: FileLockHolder) -> Bool {
        guard a.pid == b.pid, let sa = a.startTime, let sb = b.startTime else { return false }
        return abs(sa - sb) <= 1
    }

    private func run(_ holder: FileLockHolder, force: Bool) async {
        guard let path = scannedPath else { return }
        killingID = holder.id
        forceCandidate = nil
        let result = force
            ? await terminator.forceTerminate(holder, holding: path)
            : await terminator.terminate(holder, holding: path)
        killingID = nil
        Log.fileLockPeek.info("pid \(holder.pid): \(String(describing: result), privacy: .public)")

        switch result {
        case .stillRunning:
            forceCandidate = holder
            show(Banner(kind: .error, text: result.message(for: holder, path: path)))
        case .terminated:
            let name = URL(fileURLWithPath: path).lastPathComponent
            show(Banner(kind: .success, text: "✓ “\(name)” released"))
            if settings.showNotifications {
                notifier.notify(title: "“\(name)” released", body: "\(holder.processName) (PID \(holder.pid)) was terminated.")
            }
        default:
            show(Banner(kind: result.isSuccess ? .success : .error, text: result.message(for: holder, path: path)))
        }
        scan()
    }

    private func show(_ banner: Banner) {
        self.banner = banner
        bannerTask?.cancel()
        bannerTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 6_000_000_000)
            if !Task.isCancelled { self?.banner = nil }
        }
    }
}
#endif
