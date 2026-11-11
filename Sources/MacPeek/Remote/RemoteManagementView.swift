#if os(macOS)
import SwiftUI
import RemoteAgent
import RemoteCrypto

/// Settings ▸ Remote management: the off-by-default switch, pairing, paired consoles and the activity log.
struct RemoteManagementView: View {
    @EnvironmentObject private var router: UtilityRouter
    @EnvironmentObject private var remote: RemoteManagementController
    @State private var pairingRole: ConsoleRole = .viewOnly
    @State private var reachFromAnywhere = true
    @State private var joinRole: ConsoleRole = .viewAndAct

    var body: some View {
        VStack(spacing: 0) {
            PeekHeader(title: "Remote management", subtitle: remote.isEnabled ? statusText : "Off",
                       onBack: { router.go(.settings) })
            Divider()
            Form {
                Section {
                    Toggle("Allow MacPeek Remote to connect", isOn: Binding(get: { remote.isEnabled }, set: remote.setEnabled))
                    Text("When on, this Mac listens on your local network and appears as \"\(RemoteManagementController.deviceName)\" to MacPeek Remote consoles you pair with. Only paired consoles can read anything, over an end-to-end encrypted connection. When off, nothing listens and nothing is advertised.")
                        .font(.caption).foregroundStyle(.secondary)
                    if let error = remote.error {
                        Text(error).font(.caption).foregroundStyle(.orange)
                    }
                }
                if remote.isEnabled, let snapshot = remote.snapshot {
                    Section("Permissions") {
                        Toggle("Allow actions", isOn: Binding(get: { remote.allowActions }, set: remote.setAllowActions))
                        Text("Lets consoles paired to \"View and act\" free ports and quit processes, with the same safety checks as on this Mac. Every action is recorded below.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    anywhereSection(snapshot)
                    pairingSection(snapshot)
                    if let membership = snapshot.membership {
                        accountSection(membership, snapshot: snapshot)
                    } else {
                        joinSection()
                    }
                    consolesSection(snapshot)
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
            return "Available once this Mac is in a MacPeek Remote account: pair it with a console that is signed in."
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

    /// "Add to my account": for a Mac that is not on the same network as a console. Its person signs in on the web, a
    /// console of the account approves, and both screens show the same four words.
    @ViewBuilder
    private func joinSection() -> some View {
        Section("Add to a MacPeek Remote account") {
            switch remote.joinPhase {
            case .idle:
                Button("Add to my account…") {
                    joinRole = .viewAndAct
                    remote.startJoin()
                }
                Text("For a Mac away from your other Macs: sign in to your MacPeek Remote account in the browser, then approve this Mac in MacPeek Remote on your main Mac. No console is needed on this Mac. Or pair it from a console on the same network, above.")
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
                Label("Approve this Mac in MacPeek Remote, signed in as \(account.isEmpty ? "your account" : account).",
                      systemImage: "hourglass")
                    .font(.callout)
                Text("MacPeek Remote shows the request on your main Mac. Keep this window open.")
                    .font(.caption).foregroundStyle(.secondary)
                Button("Cancel", role: .cancel) { remote.cancelJoin() }
            case .confirm(let words, let account):
                Text("Check that MacPeek Remote shows these words:").font(.callout)
                Text(words.joined(separator: "  "))
                    .font(.system(size: 17, weight: .semibold, design: .rounded))
                    .frame(maxWidth: .infinity, alignment: .center)
                    .textSelection(.enabled)
                Picker("Access", selection: $joinRole) {
                    ForEach(ConsoleRole.allCases, id: \.self) { Text($0.label).tag($0) }
                }
                HStack {
                    Button("They don't match", role: .destructive) { remote.cancelJoin() }
                    Spacer()
                    Button("They match, join") { remote.confirmJoin(role: joinRole) }
                        .keyboardShortcut(.defaultAction)
                }
                Text("This adds this Mac to \(account)'s MacPeek Remote account and turns on Allow from anywhere, so every device signed in to that account can reach it from any network, with the access you choose here.")
                    .font(.caption).foregroundStyle(.secondary)
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
    private func pairingSection(_ snapshot: AgentState.Snapshot) -> some View {
        Section("Pair a console") {
            if let pending = snapshot.pendingPairing {
                Text("Check that MacPeek Remote shows these words:").font(.callout)
                Text(pending.words.joined(separator: "  "))
                    .font(.system(size: 17, weight: .semibold, design: .rounded))
                    .frame(maxWidth: .infinity, alignment: .center)
                    .textSelection(.enabled)
                Picker("Access", selection: $pairingRole) {
                    ForEach(ConsoleRole.allCases, id: \.self) { Text($0.label).tag($0) }
                }
                Toggle("Also reach this Mac from anywhere", isOn: $reachFromAnywhere)
                Text("On by default: when the console is signed in to an account, its devices keep reaching this Mac when they leave this network, through MacPeek's end-to-end encrypted relay. You can turn it off at any time under Access from anywhere.")
                    .font(.caption).foregroundStyle(.secondary)
                HStack {
                    Button("They don't match", role: .destructive) { remote.resolvePairing(role: nil) }
                    Spacer()
                    Button("They match") {
                        remote.resolvePairing(role: pairingRole)
                        if reachFromAnywhere { remote.setAllowFromAnywhere(true) }
                    }
                    .keyboardShortcut(.defaultAction)
                }
                Text(pending.console == nil ? "Waiting for the console to confirm too." :
                        "\(pending.console?.name ?? "The console") confirmed.")
                    .font(.caption).foregroundStyle(.secondary)
                if let account = pending.account {
                    Text("This adds this Mac to \(account)'s MacPeek account: every device signed in to that account can connect, with the access you choose here. You can remove it at any time.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            } else if let code = snapshot.pairingCode, !code.isExpired() {
                Text(code.formatted)
                    .font(.system(size: 28, weight: .semibold, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .center)
                    .textSelection(.enabled)
                HStack {
                    Text("Expires \(code.expiresAt, style: .relative)").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button("Cancel") { remote.cancelPairing() }
                }
                Text("Type this code in MacPeek Remote. You will then compare four words on both screens.")
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                Button("Show pairing code") {
                    pairingRole = .viewOnly
                    reachFromAnywhere = true
                    remote.showPairingCode()
                }
                Text("A code works once, for five minutes.").font(.caption).foregroundStyle(.secondary)
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
                if let moved = membership.movedFrom {
                    Button("Undo move") { remote.undoMove() }
                        .help("Pairs \(moved.identity.name) with this Mac on its own again and removes the account.")
                }
                Spacer()
                Button("Remove from account", role: .destructive) { remote.leaveAccount() }
            }
        }
    }

    @ViewBuilder
    private func consolesSection(_ snapshot: AgentState.Snapshot) -> some View {
        Section("Paired consoles") {
            if snapshot.consoles.isEmpty {
                Text("None yet.").font(.caption).foregroundStyle(.secondary)
            }
            ForEach(snapshot.consoles) { console in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Circle().fill(snapshot.connectedConsoles.contains(console.id) ? Color.green : Color.secondary.opacity(0.4))
                            .frame(width: 7, height: 7)
                            .accessibilityLabel(snapshot.connectedConsoles.contains(console.id) ? "Connected" : "Not connected")
                        Text(console.identity.name).font(.callout.weight(.medium))
                        Spacer()
                        Button("Revoke", role: .destructive) { remote.revoke(console) }
                    }
                    Text(console.identity.fingerprint).font(.caption.monospaced()).foregroundStyle(.secondary)
                    Picker("Access", selection: Binding(get: { console.role }, set: { remote.setRole($0, for: console) })) {
                        ForEach(ConsoleRole.allCases, id: \.self) { Text($0.label).tag($0) }
                    }
                    .controlSize(.small)
                }
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
#endif
