#if os(macOS)
import Foundation
import Combine
import RemoteAgent
import RemoteCrypto

/// The app's side of Remote management. Off by default: until the person turns it on nothing is created, nothing
/// listens and nothing is advertised. Turning it off stops the listener and ends every connection at once.
@MainActor
final class RemoteManagementController: ObservableObject {
    @Published private(set) var isEnabled: Bool
    @Published private(set) var allowActions: Bool
    @Published private(set) var snapshot: AgentState.Snapshot?
    @Published private(set) var listenerStatus: BonjourListener.Status = .stopped
    @Published private(set) var error: String?

    private let defaults: UserDefaults
    private var state: AgentState?
    private var listener: BonjourListener?
    private let notifications = NotificationService()

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        isEnabled = defaults.bool(forKey: "remote.enabled")
        allowActions = defaults.bool(forKey: "remote.allowActions")
        if isEnabled { start() }
    }

    var settings: RemoteSettings { RemoteSettings(isEnabled: isEnabled, allowActions: allowActions) }

    func setEnabled(_ enabled: Bool) {
        guard enabled != isEnabled else { return }
        isEnabled = enabled
        defaults.set(enabled, forKey: "remote.enabled")
        if enabled { start() } else { stop() }
    }

    func setAllowActions(_ allow: Bool) {
        allowActions = allow
        defaults.set(allow, forKey: "remote.allowActions")
        let settings = settings
        Task { await state?.update(settings) }
    }

    func showPairingCode() { Task { await state?.newPairingCode() } }
    func cancelPairing() { Task { await state?.cancelPairing() } }
    func resolvePairing(role: ConsoleRole?) { Task { await state?.resolvePairing(role: role) } }
    func setRole(_ role: ConsoleRole, for console: PairedConsole) { Task { await state?.setRole(role, for: console.id) } }
    func revoke(_ console: PairedConsole) { Task { await state?.revoke(console.id) } }
    func setAccountRole(_ role: ConsoleRole) { Task { await state?.setWorkspaceRoleCap(role) } }
    func leaveAccount() { Task { await state?.leaveWorkspace() } }
    func undoMove() { Task { await state?.undoMove() } }

    private func start() {
        do {
            let state = try self.state ?? makeState()
            self.state = state
            let settings = settings
            let listener = BonjourListener(state: state, handler: RequestHandler(readers: .system(), actions: .system(),
                                                                                 agentVersion: Self.appVersion),
                                           name: Self.deviceName) { [weak self] status in
                let controller = self
                Task { @MainActor in controller?.listenerStatus = status }
            }
            self.listener = listener
            Task {
                await state.update(settings)
                // Switched off (or restarted) while the settings were applied: never start a listener nothing can stop.
                guard self.listener === listener, self.isEnabled else { return }
                listener.start()
                await refresh()
            }
            error = nil
        } catch {
            self.error = "Could not load this Mac's identity from the Keychain."
            isEnabled = false
            defaults.set(false, forKey: "remote.enabled")
        }
    }

    private func stop() {
        listener?.stop()
        listener = nil
        let settings = settings
        Task {
            await state?.update(settings)
            await refresh()
        }
    }

    private func makeState() throws -> AgentState {
        let identity = try KeychainIdentityStore().loadOrCreate(name: Self.deviceName)
        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("MacPeek/Remote", isDirectory: true)
        let state = AgentState(identity: identity, store: FileAgentStore(directory: directory))
        Task {
            await state.setOnChange { [weak self] in
                let controller = self
                Task { @MainActor in await controller?.refresh() }
            }
        }
        return state
    }

    private func refresh() async {
        let hadSnapshot = snapshot != nil
        let before = snapshot?.membership
        snapshot = await state?.snapshot()
        // A console moved this Mac into its account: that lets every device of the account in, so say so even when
        // Settings is closed. "Undo move" is in Settings ▸ Remote management.
        if hadSnapshot, let after = snapshot?.membership, let console = after.movedFrom, before?.workspaceID != after.workspaceID {
            notifications.notify(title: "This Mac was added to \(after.name)'s account",
                                 body: "\(console.identity.name) moved it. Every device in that account can now connect. To undo it, open MacPeek ▸ Settings ▸ Remote management.")
        }
    }

    static var deviceName: String { Host.current().localizedName ?? "Mac" }

    static var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "development"
    }
}
#endif
