#if os(macOS)
import SwiftUI
import MacPeekCore
import ContainerPeekKit

/// ContainerPeek's screen: each engine's containers (running first), then virtual machines and the hypervisor
/// processes behind them.
struct ContainerPeekView: View {
    @EnvironmentObject private var store: ContainerStore

    var body: some View {
        VStack(spacing: 0) {
            HStack { SearchField(text: $store.query, prompt: "Name, image, project or port…") }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            Divider()
            if let banner = store.banner { BannerView(banner: banner) }
            if let error = store.error, store.snapshot != nil {
                BannerView(banner: Banner(kind: .error, text: "Couldn't refresh: \(error) Showing the last reading."))
            }
            content
            Divider()
            footer
        }
    }

    @ViewBuilder private var content: some View {
        if let error = store.error, store.snapshot == nil {
            ErrorState(message: error, retryTitle: "Try again") { Task { await store.refreshOnce() } }
        } else if let snapshot = store.snapshot {
            if snapshot.nothingInstalled {
                EmptyState(symbol: "shippingbox", title: "No container engine or VM manager found",
                           message: "MacPeek looks for docker, podman, limactl, colima, tart and prlctl in /opt/homebrew/bin, /usr/local/bin and the apps' own folders.")
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(snapshot.engines) { engine in EngineSection(engine: engine) }
                        if !snapshot.virtualMachines.isEmpty || !snapshot.vmProcesses.isEmpty || !snapshot.notes.isEmpty {
                            VMSection(snapshot: snapshot)
                        }
                    }
                    .padding(12)
                }
                .frame(maxHeight: .infinity)
            }
        } else {
            VStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Asking your container engines…").font(.caption).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var footer: some View {
        HStack {
            Text("CPU and memory as each engine reports them")
            Spacer()
            if store.isLoading { ProgressView().controlSize(.small) }
            Button { Task { await store.refreshOnce() } } label: { Image(systemName: "arrow.clockwise") }
                .buttonStyle(.borderless)
                .help("Refresh now")
                .keyboardShortcut("r", modifiers: .command)
                .accessibilityLabel("Refresh containers")
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }
}

private struct EngineSection: View {
    @EnvironmentObject private var store: ContainerStore
    let engine: ContainerEngineReport

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionLabel(text: engine.kind.displayName + (engine.context.map { " · \($0)" } ?? ""),
                         trailing: engine.status == .running ? "\(engine.runningCount) of \(engine.containers.count) running" : nil)
            switch engine.status {
            case .running:
                let containers = store.visible(engine)
                if engine.containers.isEmpty {
                    Text("No containers.").font(.caption).foregroundStyle(.secondary)
                } else if containers.isEmpty {
                    Text("No containers match.").font(.caption).foregroundStyle(.secondary)
                }
                if let note = engine.statsNote { Text(note).font(.caption2).foregroundStyle(.orange) }
                VStack(spacing: 0) {
                    ForEach(containers) { container in
                        ContainerRow(container: container, engine: engine.kind)
                        Divider().opacity(0.4)
                    }
                }
                .peekCard()
            case .notRunning(let message):
                Label(message, systemImage: "pause.circle").font(.caption).foregroundStyle(.secondary).peekCard()
            case .failed(let message):
                Label(message, systemImage: "exclamationmark.triangle").font(.caption).foregroundStyle(.orange).peekCard()
            }
        }
    }
}

private struct ContainerRow: View {
    @EnvironmentObject private var store: ContainerStore
    let container: ContainerInfo
    let engine: ContainerEngineKind
    @State private var confirming: ContainerAction?

    private var expanded: Bool { store.expandedID == container.id }
    private var busy: Bool { store.busyContainerID == container.id }

    private var tone: StatusBadge.Tone {
        switch container.state {
        case .running: return .good
        case .paused, .restarting: return .warning
        default: return .neutral
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(container.name).font(.system(size: 13, weight: .medium)).lineLimit(1)
                    Text(subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer(minLength: 4)
                if let stats = container.stats {
                    VStack(alignment: .trailing, spacing: 0) {
                        if let cpu = stats.cpuPercent { Text(String(format: "%.1f%% CPU", cpu)).font(.caption.monospacedDigit()) }
                        if let memory = stats.memoryUsedBytes { Text(ByteCountText.memory(memory)).font(.caption2.monospacedDigit()).foregroundStyle(.secondary) }
                    }
                }
                StatusBadge(text: container.state.label, tone: tone)
            }
            .contentShape(Rectangle())
            .onTapGesture { withAnimation(.easeOut(duration: 0.15)) { store.expandedID = expanded ? nil : container.id } }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isButton)

            if expanded { details }
        }
        .padding(.vertical, 6)
    }

    private var subtitle: String {
        var parts = [container.image]
        let published = container.publishedPorts.compactMap(\.hostPort).map(String.init)
        if !published.isEmpty { parts.append("ports " + published.joined(separator: ", ")) }
        if let project = container.composeProject { parts.append(project) }
        return parts.joined(separator: " · ")
    }

    @ViewBuilder private var details: some View {
        VStack(alignment: .leading, spacing: 8) {
            KeyValueRows(rows: rows)
            if !container.ports.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Ports").font(.caption).foregroundStyle(.secondary)
                    ForEach(container.ports, id: \.self) { port in Text(port.label).font(.caption.monospaced()) }
                }
            }
            actions
            logsView
        }
    }

    private var rows: [(label: String, value: String)] {
        var rows: [(label: String, value: String)] = [("ID", container.shortID), ("Status", container.status)]
        if let service = container.composeService { rows.append(("Compose", "\(container.composeProject ?? "?") / \(service)")) }
        if let created = container.createdAt { rows.append(("Created", created)) }
        if let stats = container.stats {
            if let used = stats.memoryUsedBytes {
                let limit = stats.memoryLimitBytes.map { " of " + ByteCountText.memory($0) } ?? ""
                rows.append(("Memory", ByteCountText.memory(used) + limit))
            }
            if let pids = stats.pids { rows.append(("Processes", String(pids))) }
        }
        return rows
    }

    @ViewBuilder private var actions: some View {
        if let action = confirming {
            KillConfirmationView(
                title: confirmTitle(action),
                confirmLabel: action.title,
                destructive: action == .remove,
                onCancel: { confirming = nil },
                onConfirm: { confirming = nil; store.perform(action, on: container, engine: engine) })
        } else {
            HStack(spacing: 6) {
                ForEach(container.availableActions, id: \.self) { action in
                    Button(action.title, role: action == .remove ? .destructive : nil) {
                        if action.needsConfirmation { confirming = action } else { store.perform(action, on: container, engine: engine) }
                    }
                    .disabled(busy)
                }
                if busy { ProgressView().controlSize(.small) }
                Spacer()
            }
            .controlSize(.small)
        }
    }

    private func confirmTitle(_ action: ContainerAction) -> String {
        switch action {
        case .remove: return "Remove \(container.name)? Its volumes and image are kept."
        case .stop: return "Stop \(container.name)?"
        case .restart: return "Restart \(container.name)?"
        default: return "\(action.title) \(container.name)?"
        }
    }

    @ViewBuilder private var logsView: some View {
        switch store.logs[container.id] {
        case nil:
            Button("Show recent logs") { store.loadLogs(of: container, engine: engine) }.controlSize(.small)
        case .loading?:
            HStack(spacing: 6) { ProgressView().controlSize(.small); Text("Reading logs…").font(.caption).foregroundStyle(.secondary) }
        case .failed(let message)?:
            Text(message).font(.caption).foregroundStyle(.orange)
        case .loaded(let logs)?:
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Last \(logs.lines.count) lines").font(.caption).foregroundStyle(.secondary)
                    CopyButton(text: logs.lines.joined(separator: "\n"), label: "Copy logs")
                    Spacer()
                    Button("Hide") { store.hideLogs(of: container) }.controlSize(.small)
                }
                ScrollView {
                    Text(logs.lines.isEmpty ? "(no output)" : logs.lines.joined(separator: "\n"))
                        .font(.system(size: 10.5, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 160)
                Text("Logs can contain secrets. They are shown here only and never saved or logged.")
                    .font(.caption2).foregroundStyle(.tertiary)
            }
        }
    }
}

private struct VMSection: View {
    let snapshot: ContainerSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionLabel(text: "Virtual machines", trailing: snapshot.virtualMachines.isEmpty ? nil : "\(snapshot.runningVMs) running")
            if !snapshot.virtualMachines.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(snapshot.virtualMachines) { vm in
                        HStack(spacing: 8) {
                            VStack(alignment: .leading, spacing: 1) {
                                Text(vm.name).font(.system(size: 13, weight: .medium)).lineLimit(1)
                                Text(vmSubtitle(vm)).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                            }
                            Spacer(minLength: 4)
                            StatusBadge(text: vm.state.capitalized, tone: vm.isRunning ? .good : .neutral)
                        }
                    }
                }
                .peekCard()
            }
            if !snapshot.vmProcesses.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Hypervisor processes on this Mac").font(.caption.weight(.semibold))
                    ForEach(snapshot.vmProcesses) { process in
                        HStack {
                            Text("\(process.kind) · PID \(process.pid)").font(.caption).lineLimit(1)
                            Spacer()
                            Text(process.cpuPercent.map { String(format: "%.0f%% CPU", $0) } ?? "—").font(.caption.monospacedDigit())
                            Text(ByteCountText.memory(process.memoryFootprintBytes)).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                                .frame(width: 70, alignment: .trailing)
                        }
                    }
                    Text("What macOS counts for the processes that run VMs (including Docker Desktop's, OrbStack's and Colima's), whichever tool started them. CPU is percent of one core, sampled.")
                        .font(.caption2).foregroundStyle(.tertiary)
                }
                .peekCard()
            }
            ForEach(snapshot.notes, id: \.self) { note in Text(note).font(.caption2).foregroundStyle(.orange) }
        }
    }

    private func vmSubtitle(_ vm: VirtualMachine) -> String {
        var parts = [vm.source.displayName]
        if let cpus = vm.cpus { parts.append("\(cpus) CPU") }
        if let memory = vm.memoryBytes { parts.append(ByteCountText.memory(memory) + " RAM") }
        if let detail = vm.detail { parts.append(detail) }
        return parts.joined(separator: " · ")
    }
}
#endif
