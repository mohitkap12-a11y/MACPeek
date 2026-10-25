#if os(macOS)
import SwiftUI
import RemoteAgent
import RemoteCrypto

/// Settings ▸ Remote management: the off-by-default switch, pairing, paired consoles and the activity log.
struct RemoteManagementView: View {
    @EnvironmentObject private var router: UtilityRouter
    @EnvironmentObject private var remote: RemoteManagementController
    @State private var pairingRole: ConsoleRole = .viewOnly

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
                    pairingSection(snapshot)
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
        case .listening: return "On · listening on the local network"
        case .starting: return "Starting…"
        case .failed(let message): return "Not listening: \(message)"
        case .stopped: return "On"
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
                HStack {
                    Button("They don't match", role: .destructive) { remote.resolvePairing(role: nil) }
                    Spacer()
                    Button("They match") { remote.resolvePairing(role: pairingRole) }
                        .keyboardShortcut(.defaultAction)
                }
                Text(pending.console == nil ? "Waiting for the console to confirm too." :
                        "\(pending.console?.name ?? "The console") confirmed.")
                    .font(.caption).foregroundStyle(.secondary)
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
                    remote.showPairingCode()
                }
                Text("A code works once, for five minutes.").font(.caption).foregroundStyle(.secondary)
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
