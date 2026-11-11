#if os(macOS)
import Foundation
import Combine
import AppKit
import RemoteAgent
import RemoteCrypto

/// The app's side of Remote management. Off by default: until the person turns it on nothing is created, nothing
/// listens and nothing is advertised. Turning it off stops the listener and ends every connection at once.
///
/// "Allow from anywhere" is a second switch, also off by default: while it is on and this Mac is in a MacPeek Remote
/// account, the Mac keeps one outbound connection to the relay so the account's devices reach it from any network.
@MainActor
final class RemoteManagementController: ObservableObject {
    @Published private(set) var isEnabled: Bool
    @Published private(set) var allowActions: Bool
    @Published private(set) var allowFromAnywhere: Bool
    @Published private(set) var relayStatus: RelayClient.Status = .off
    /// "Add to my account" (AccountJoinFlow), shown in Settings while this Mac is in no account.
    @Published private(set) var joinPhase: AccountJoinFlow.Phase = .idle
    @Published private(set) var snapshot: AgentState.Snapshot?
    @Published private(set) var listenerStatus: BonjourListener.Status = .stopped
    @Published private(set) var error: String?

    private let defaults: UserDefaults
    private var state: AgentState?
    private var listener: BonjourListener?
    private var relay: RelayClient?
    private var handler: RequestHandler?
    private var identity: DeviceIdentity?
    private var joinFlow: AccountJoinFlow?
    private var joinWork: Task<Void, Never>?
    private let notifications = NotificationService()

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        isEnabled = defaults.bool(forKey: "remote.enabled")
        allowActions = defaults.bool(forKey: "remote.allowActions")
        allowFromAnywhere = defaults.bool(forKey: "remote.allowFromAnywhere")
        if isEnabled { start() }
    }

    var settings: RemoteSettings {
        RemoteSettings(isEnabled: isEnabled, allowActions: allowActions, allowFromAnywhere: allowFromAnywhere)
    }

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

    func setAllowFromAnywhere(_ allow: Bool) {
        guard allow != allowFromAnywhere else { return }
        allowFromAnywhere = allow
        defaults.set(allow, forKey: "remote.allowFromAnywhere")
        let settings = settings
        Task {
            await state?.update(settings)
            await refresh()
        }
    }

    /// Starts "Add to my account": asks the service, opens the sign-in page in the browser, then checks every few seconds
    /// until a console of the account approves (or the request ends).
    func startJoin() {
        guard isEnabled, let state, let identity else { return }
        joinWork?.cancel()
        let flow = AccountJoinFlow(state: state, identity: identity, name: Self.deviceName, http: URLSessionAccountHTTP()) { [weak self] phase in
            let controller = self
            Task { @MainActor in controller?.joinChanged(phase) }
        }
        joinFlow = flow
        joinWork = Task {
            await flow.start()
            if case .signIn(let url) = await flow.phase { NSWorkspace.shared.open(url) }
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                guard !Task.isCancelled else { return }
                await flow.poll()
                switch await flow.phase {
                case .signIn, .waitingForApproval: continue
                default: return
                }
            }
        }
    }

    func openJoinPage(_ url: URL) { NSWorkspace.shared.open(url) }

    /// The words matched: join with `role`.
    func confirmJoin(role: ConsoleRole) {
        guard let joinFlow else { return }
        Task { await joinFlow.join(role: role) }
    }

    /// The words did not match, or the person changed their mind.
    func cancelJoin() {
        joinWork?.cancel()
        joinWork = nil
        let flow = joinFlow
        joinFlow = nil
        joinPhase = .idle
        Task { await flow?.cancel() }
    }

    private func joinChanged(_ phase: AccountJoinFlow.Phase) {
        guard joinFlow != nil else { return }
        joinPhase = phase
        if case .joined(let account) = phase {
            // The point of adding a Mac from the Mac: its account reaches it from anywhere. Settings says so.
            setAllowFromAnywhere(true)
            notifications.notify(title: "This Mac is in \(account)'s account",
                                 body: "Its devices can now reach it from anywhere through MacPeek's encrypted relay. Turn this off in MacPeek ▸ Settings ▸ Remote management.")
        }
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
            let handler = self.handler ?? RequestHandler(readers: .system(), actions: .system(), agentVersion: Self.appVersion)
            self.handler = handler
            let listener = BonjourListener(state: state, handler: handler, name: Self.deviceName) { [weak self] status in
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
        stopRelay()
        cancelJoin()
        let settings = settings
        Task {
            await state?.update(settings)
            await refresh()
        }
    }

    private func makeState() throws -> AgentState {
        let identity = try KeychainIdentityStore().loadOrCreate(name: Self.deviceName)
        self.identity = identity
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
        updateRelay(movedFrom: before?.workspaceID)
        // A console moved this Mac into its account: that lets every device of the account in, so say so even when
        // Settings is closed. "Undo move" is in Settings ▸ Remote management.
        if hadSnapshot, let after = snapshot?.membership, let console = after.movedFrom, before?.workspaceID != after.workspaceID {
            notifications.notify(title: "This Mac was added to \(after.name)'s account",
                                 body: "\(console.identity.name) moved it. Every device in that account can now connect. To undo it, open MacPeek ▸ Settings ▸ Remote management.")
        }
    }

    /// Runs the relay connection exactly while Remote management and Allow from anywhere are on and this Mac is in an
    /// account; reconnects when the Mac moves to another account, so the relay checks the new claim.
    private func updateRelay(movedFrom previousWorkspace: String?) {
        let membership = snapshot?.membership
        guard isEnabled, allowFromAnywhere, membership != nil, let state, let handler, let identity else {
            stopRelay()
            return
        }
        if let relay {
            if previousWorkspace != nil, previousWorkspace != membership?.workspaceID {
                Task { await relay.reconnectNow() }
            }
            return
        }
        let relay = RelayClient(state: state, handler: handler, identity: identity,
                                makeSocket: URLSessionRelaySocket.factory) { [weak self] status in
            let controller = self
            Task { @MainActor in controller?.relayStatus = status }
        }
        self.relay = relay
        Task { await relay.start() }
    }

    private func stopRelay() {
        guard let relay else { return }
        self.relay = nil
        relayStatus = .off
        Task { await relay.stop() }
    }

    static var deviceName: String { Host.current().localizedName ?? "Mac" }

    static var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "development"
    }
}
#endif
