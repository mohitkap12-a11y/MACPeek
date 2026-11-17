#if os(macOS)
import SwiftUI
import RemoteAgent
import RemoteCrypto
import RemoteProtocol

/// Settings ▸ Remote management: the off-by-default switch, adding this Mac to a MacPeek Remote account (or the account
/// it belongs to), access from anywhere, and the activity log.
struct RemoteManagementView: View {
    @EnvironmentObject private var router: UtilityRouter
    @EnvironmentObject private var remote: RemoteManagementController

    var body: some View {
        VStack(spacing: 0) {
            PeekHeader(title: "Remote management", subtitle: remote.isEnabled ? statusText : "Off",
                       onBack: { router.go(.settings) })
            Divider()
            Form {
                Section {
                    Toggle("Allow MacPeek Remote to connect", isOn: Binding(get: { remote.isEnabled }, set: remote.setEnabled))
                    Text("When on, devices of the MacPeek Remote account you add this Mac to can reach it as \"\(RemoteManagementController.deviceName)\", over an end-to-end encrypted connection. Nobody else can read anything. When off, nothing listens and nothing is advertised.")
                        .font(.caption).foregroundStyle(.secondary)
                    if let error = remote.error {
                        Text(error).font(.caption).foregroundStyle(.orange)
                    }
                }
                if remote.isEnabled, let snapshot = remote.snapshot {
                    Section("Permissions") {
                        Toggle("Allow actions", isOn: Binding(get: { remote.allowActions }, set: remote.setAllowActions))
                        Text("Lets your account's devices free ports, quit processes and manage containers, with the same safety checks as on this Mac. Off until you turn it on. Every action is recorded below.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    if let membership = snapshot.membership {
                        accountSection(membership, snapshot: snapshot)
                        anywhereSection(snapshot)
                        TunnelsSection(snapshot: snapshot)
                    } else {
                        joinSection()
                    }
                    activitySection(snapshot)
                    Section("This Mac") {
                        LabeledContent("Key fingerprint") {
                            Text(snapshot.identity.fingerprint).font(.caption.monospaced()).textSelection(.enabled)
                        }
                    }
                }
            }
            .formStyle(.grouped)
        }
    }

    private var statusText: String {
        switch remote.listenerStatus {
        case .listening:
            return remote.relayStatus == .connected ? "On · local network and anywhere" : "On · listening on the local network"
        case .starting: return "Starting…"
        case .failed(let message): return "Not listening: \(message)"
        case .stopped: return "On"
        }
    }

    @ViewBuilder
    private func anywhereSection(_ snapshot: AgentState.Snapshot) -> some View {
        Section("Access from anywhere") {
            Toggle("Allow from anywhere", isOn: Binding(get: { remote.allowFromAnywhere }, set: remote.setAllowFromAnywhere))
                .disabled(snapshot.membership == nil && !remote.allowFromAnywhere)
            Text("Lets the devices of this Mac's MacPeek Remote account reach it from any network, through MacPeek's relay, without opening a port. The connection stays end-to-end encrypted: the relay sees only which Mac and which of your devices connect, addresses, times and amounts of data. Actions still need \"Allow actions\".")
                .font(.caption).foregroundStyle(.secondary)
            if remote.allowFromAnywhere || snapshot.membership == nil {
                Label(relayText(snapshot), systemImage: relayIcon(snapshot))
                    .font(.caption)
                    .foregroundStyle(remote.relayStatus == .connected ? Color.green : Color.secondary)
            }
        }
    }

    private func relayText(_ snapshot: AgentState.Snapshot) -> String {
        if snapshot.membership == nil {
            return "Available once this Mac is in a MacPeek Remote account: choose Add to my account."
        }
        switch remote.relayStatus {
        case .off: return "Off"
        case .connecting: return "Connecting to the relay…"
        case .connected: return "Reachable from anywhere"
        case .notInAccount: return "The relay does not know this Mac's account yet. It will try again shortly."
        case .waiting(let retryAt, let reason):
            return "\(reason) Trying again \(retryAt.formatted(.relative(presentation: .named)))."
        }
    }

    private func relayIcon(_ snapshot: AgentState.Snapshot) -> String {
        if snapshot.membership == nil { return "person.crop.circle.badge.questionmark" }
        switch remote.relayStatus {
        case .connected: return "globe"
        case .connecting: return "arrow.triangle.2.circlepath"
        default: return "exclamationmark.triangle"
        }
    }

    /// "Add to my account", the only way to add this Mac: its person signs in on the web, MacPeek Remote on their main Mac
    /// approves, and the Mac joins with View and act and Allow from anywhere on.
    @ViewBuilder
    private func joinSection() -> some View {
        Section("MacPeek Remote account") {
            switch remote.joinPhase {
            case .idle:
                Button("Add to my account…") { remote.startJoin() }
                Text("Sign in to your MacPeek Remote account in the browser, then approve this Mac in MacPeek Remote on your main Mac. It is then reachable on this network and from anywhere.")
                    .font(.caption).foregroundStyle(.secondary)
            case .starting:
                ProgressView("Asking MacPeek Remote…").controlSize(.small)
            case .signIn(let url):
                Text("Sign in to your MacPeek Remote account in the browser window that opened, then choose Add.").font(.callout)
                HStack {
                    Button("Open the page again") { remote.openJoinPage(url) }
                    Spacer()
                    Button("Cancel", role: .cancel) { remote.cancelJoin() }
                }
            case .waitingForApproval(let account):
                Label("Approve this Mac in MacPeek Remote on your main Mac\(account.isEmpty ? "" : ", signed in as \(account)").",
                      systemImage: "hourglass")
                    .font(.callout)
                Text("This Mac joins as soon as you approve it there.").font(.caption).foregroundStyle(.secondary)
                Button("Cancel", role: .cancel) { remote.cancelJoin() }
            case .joining:
                ProgressView("Joining…").controlSize(.small)
            case .joined(let account):
                Label("Added to \(account)'s account", systemImage: "checkmark.circle").foregroundStyle(.green)
            case .failed(let message):
                Text(message).font(.caption).foregroundStyle(.orange)
                Button("Try again") { remote.startJoin() }
            }
        }
    }

    @ViewBuilder
    private func accountSection(_ membership: WorkspaceMembership, snapshot: AgentState.Snapshot) -> some View {
        Section("Account") {
            LabeledContent("Belongs to") { Text("\(membership.name)'s account") }
            Picker("Access", selection: Binding(get: { membership.roleCap }, set: remote.setAccountRole)) {
                ForEach(ConsoleRole.allCases, id: \.self) { Text($0.label).tag($0) }
            }
            Text("Every device signed in to this account can connect, with at most this access. Devices removed from the account are refused as soon as one of its consoles tells this Mac.")
                .font(.caption).foregroundStyle(.secondary)
            ForEach(membership.devices.sorted { $0.lastConnected > $1.lastConnected }) { device in
                HStack {
                    Circle().fill(snapshot.connectedConsoles.contains(device.id) ? Color.green : Color.secondary.opacity(0.4))
                        .frame(width: 7, height: 7)
                        .accessibilityLabel(snapshot.connectedConsoles.contains(device.id) ? "Connected" : "Not connected")
                    Text(device.identity.name).font(.callout)
                    Spacer()
                    Text(device.lastConnected, style: .relative).font(.caption).foregroundStyle(.secondary)
                }
            }
            HStack {
                Spacer()
                Button("Remove from account", role: .destructive) { remote.leaveAccount() }
            }
        }
    }

    @ViewBuilder
    private func activitySection(_ snapshot: AgentState.Snapshot) -> some View {
        Section("Activity") {
            let entries = snapshot.log.entries.suffix(20).reversed()
            if entries.isEmpty {
                Text("Nothing yet.").font(.caption).foregroundStyle(.secondary)
            }
            ForEach(Array(entries)) { entry in
                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.event).font(.caption)
                    Text("\(entry.actor) · \(entry.outcome) · \(entry.date.formatted(date: .abbreviated, time: .shortened))")
                        .font(.caption2).foregroundStyle(.secondary)
                }
            }
            if !snapshot.log.isIntact {
                Text("The activity log has been changed outside MacPeek.").font(.caption).foregroundStyle(.orange)
            }
        }
    }
}
/// Settings ▸ Remote management ▸ Tunnels (Pro): which ports of this Mac the account's devices may reach through a
/// tunnel, and the tunnels open now, each with Close.
private struct TunnelsSection: View {
    @EnvironmentObject private var remote: RemoteManagementController
    let snapshot: AgentState.Snapshot
    @State private var portsText = ""
    @State private var portsProblem: String?

    var body: some View {
        Section("Tunnels") {
            Picker("Allow tunnels", selection: Binding(get: { remote.tunnels.mode }, set: setMode)) {
                Text("Off").tag(TunnelPolicy.Mode.off)
                Text("SSH only").tag(TunnelPolicy.Mode.ssh)
                Text("SSH and these ports").tag(TunnelPolicy.Mode.sshAndPorts)
                Text("Any port").tag(TunnelPolicy.Mode.anyPort)
            }
            if remote.tunnels.mode == .sshAndPorts {
                TextField("Ports, e.g. 3000, 5432", text: $portsText)
                    .onSubmit(savePorts)
                    .onAppear { portsText = remote.tunnels.ports.map(String.init).joined(separator: ", ") }
                if let portsProblem { Text(portsProblem).font(.caption).foregroundStyle(.orange) }
            }
            Text("Lets your account's devices with View and act reach a port on this Mac, such as its SSH server or a dev server, as if it were on theirs: on the local network, or from anywhere with MacPeek Remote Pro. Tunnels only reach this Mac itself, never other computers on its network. Each one is shown here and in the menu bar while it is open, and recorded below.")
                .font(.caption).foregroundStyle(.secondary)
            if remote.tunnels.allows(TunnelPolicy.sshPort) {
                Text("SSH needs Remote Login on in System Settings ▸ General ▸ Sharing.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            ForEach(snapshot.tunnels) { tunnel in
                HStack {
                    Image(systemName: "arrow.left.arrow.right").foregroundStyle(.green)
                    VStack(alignment: .leading) {
                        Text("Port \(tunnel.port) · \(tunnel.consoleName)").font(.callout)
                        Text("\(tunnel.viaRelay ? "Through the relay" : "On the local network") · since \(tunnel.openedAt.formatted(date: .omitted, time: .shortened))")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Close") { remote.closeTunnel(tunnel.id) }
                }
            }
        }
    }

    private func setMode(_ mode: TunnelPolicy.Mode) {
        portsProblem = nil
        let ports = mode == .sshAndPorts ? (TunnelPolicy.parsePorts(portsText) ?? remote.tunnels.ports) : remote.tunnels.ports
        remote.setTunnels(TunnelPolicy(mode: mode, ports: ports))
    }

    private func savePorts() {
        guard let ports = TunnelPolicy.parsePorts(portsText) else {
            portsProblem = "Use port numbers from 1 to 65535, separated by commas."
            return
        }
        portsProblem = nil
        remote.setTunnels(TunnelPolicy(mode: .sshAndPorts, ports: ports))
        portsText = TunnelPolicy(mode: .sshAndPorts, ports: ports).ports.map(String.init).joined(separator: ", ")
    }
}
#endif
