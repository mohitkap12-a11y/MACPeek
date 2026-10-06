#if os(macOS)
import SwiftUI
import PortPeekCore

struct PortDetailView: View {
    @EnvironmentObject private var store: PortStore
    @EnvironmentObject private var settings: AppSettings
    let port: PortInfo
    @State private var confirming = false

    private var capability: TerminationCapability { store.capability(for: port) }
    private var busy: Bool { store.killingID == port.id }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 4) {
                row("Process", port.processName)
                row("PID", String(port.pid))
                row("Protocol", port.protocolType.rawValue)
                row("Address", port.endpoint)
                if let state = port.state { row("State", state.label) }
                if let user = port.user { row("User", user) }
            }
            .font(.system(size: 12))

            capabilityLabel

            if store.forceCandidate?.id == port.id {
                forcePrompt
            } else if confirming {
                KillConfirmationView(
                    port: port,
                    title: "Terminate \(port.processName) (PID \(port.pid))?",
                    confirmLabel: "Terminate",
                    destructive: false,
                    onCancel: { confirming = false },
                    onConfirm: { confirming = false; Task { await store.terminate(port) } }
                )
            } else {
                HStack {
                    Button(role: .destructive) {
                        if settings.confirmBeforeKill { confirming = true } else { Task { await store.terminate(port) } }
                    } label: {
                        if busy { ProgressView().controlSize(.small) } else { Text("Kill Process") }
                    }
                    .disabled(busy || capability == .protected)
                    .keyboardShortcut(.delete, modifiers: .command)
                    Spacer()
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 10)
    }

    private var forcePrompt: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("\(port.processName) did not exit after a graceful request (SIGTERM). Force-killing ends it immediately and it cannot save its state.")
                .font(.caption).foregroundStyle(.secondary)
            KillConfirmationView(
                port: port,
                title: "Force kill PID \(port.pid)?",
                confirmLabel: "Force Kill",
                destructive: true,
                onCancel: { store.dismissForce() },
                onConfirm: { Task { await store.forceTerminate(port) } }
            )
        }
    }

    @ViewBuilder private var capabilityLabel: some View {
        switch capability {
        case .canTerminate: Label("Can terminate", systemImage: "checkmark.circle").foregroundStyle(.green)
        case .permissionRequired: Label("Permission required", systemImage: "exclamationmark.triangle").foregroundStyle(.orange)
        case .protected: Label("Protected/system process", systemImage: "lock.fill").foregroundStyle(.secondary)
        }
    }

    private func row(_ label: String, _ value: String) -> some View {
        GridRow {
            Text(label).foregroundStyle(.secondary)
            Text(value).textSelection(.enabled)
        }
    }
}
#endif
