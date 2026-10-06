#if os(macOS)
import SwiftUI
import AppKit
import MacPeekCore
import FileLockPeekKit

struct FileHolderRowView: View {
    @EnvironmentObject private var store: FileLockStore
    @EnvironmentObject private var settings: AppSettings
    let holder: FileLockHolder
    @State private var confirming = false

    private var expanded: Bool { store.selectedID == holder.id }
    private var capability: TerminationCapability { store.capability(for: holder) }
    private var busy: Bool { store.killingID == holder.id }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(holder.processName).font(.system(size: 13, weight: .medium)).lineLimit(1)
                    Text("PID \(holder.pid)").font(.caption).foregroundStyle(.secondary)
                }
                Spacer(minLength: 4)
                if holder.hasLock { StatusBadge(text: "Locked", tone: .warning) }
                StatusBadge(text: badge(for: holder.primaryKind), tone: .neutral)
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.tertiary)
                    .rotationEffect(.degrees(expanded ? 90 : 0))
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
            .onTapGesture { withAnimation(.easeOut(duration: 0.15)) { store.selectedID = expanded ? nil : holder.id } }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isButton)

            if expanded { details }
        }
        .background(expanded ? Color.accentColor.opacity(0.08) : .clear)
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: 10) {
            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 4) {
                GridRow {
                    Text("Process").foregroundStyle(.secondary)
                    HStack(spacing: 6) { Text(holder.processName); CopyButton(text: holder.processName, label: "Copy process name") }
                }
                GridRow {
                    Text("PID").foregroundStyle(.secondary)
                    HStack(spacing: 6) { Text(String(holder.pid)); CopyButton(text: String(holder.pid), label: "Copy PID") }
                }
                if let user = holder.user {
                    GridRow { Text("User").foregroundStyle(.secondary); Text(user) }
                }
            }
            .font(.system(size: 12))

            VStack(alignment: .leading, spacing: 4) {
                Text("HOLDS").font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary)
                ForEach(Array(holder.files.prefix(8).enumerated()), id: \.offset) { _, file in
                    VStack(alignment: .leading, spacing: 0) {
                        Text(file.path).font(.system(size: 11, design: .monospaced)).lineLimit(1).truncationMode(.middle)
                        Text(describe(file)).font(.caption2).foregroundStyle(.secondary)
                    }
                }
                if holder.files.count > 8 {
                    Text("and \(holder.files.count - 8) more").font(.caption2).foregroundStyle(.secondary)
                }
            }

            capabilityLabel

            HStack(spacing: 8) {
                if let path = store.scannedPath {
                    Button("Reveal in Finder") { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)]) }
                    Button("Copy path") { copy(path) }
                }
            }
            .controlSize(.small)

            actions
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 10)
    }

    @ViewBuilder private var actions: some View {
        if store.forceCandidate?.id == holder.id {
            VStack(alignment: .leading, spacing: 6) {
                Text("\(holder.processName) did not exit after a graceful request (SIGTERM). Force-killing ends it immediately and it cannot save its state.")
                    .font(.caption).foregroundStyle(.secondary)
                KillConfirmationView(
                    title: "Force kill PID \(holder.pid)?",
                    confirmLabel: "Force Kill",
                    destructive: true,
                    onCancel: { store.dismissForce() },
                    onConfirm: { Task { await store.confirmForceTerminate() } }
                )
            }
        } else if confirming {
            KillConfirmationView(
                title: "Terminate \(holder.processName) (PID \(holder.pid))?",
                confirmLabel: "Terminate",
                destructive: false,
                onCancel: { confirming = false },
                onConfirm: { confirming = false; Task { await store.terminate(holder) } }
            )
        } else {
            HStack {
                Button(role: .destructive) {
                    if settings.confirmBeforeKill { confirming = true } else { Task { await store.terminate(holder) } }
                } label: {
                    if busy { ProgressView().controlSize(.small) } else { Text("Kill Process") }
                }
                .disabled(busy || capability == .protected)
                Spacer()
            }
        }
    }

    @ViewBuilder private var capabilityLabel: some View {
        switch capability {
        case .canTerminate: Label("Can terminate", systemImage: "checkmark.circle").foregroundStyle(.green)
        case .permissionRequired: Label("Permission required", systemImage: "exclamationmark.triangle").foregroundStyle(.orange)
        case .protected: Label("Protected/system process", systemImage: "lock.fill").foregroundStyle(.secondary)
        }
    }

    private func badge(for kind: HoldKind) -> String {
        switch kind {
        case .open(let access): return "Open · \(access.label)"
        case .workingDirectory: return "Working dir"
        case .executable: return "Executable"
        case .memoryMapped: return "Mapped"
        case .other(let raw): return raw
        }
    }

    private func describe(_ file: OpenFile) -> String {
        [file.kind.label, file.lock].compactMap { $0 }.joined(separator: " · ")
    }

    private func copy(_ string: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(string, forType: .string)
    }
}
#endif
