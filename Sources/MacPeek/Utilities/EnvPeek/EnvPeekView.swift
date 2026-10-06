#if os(macOS)
import SwiftUI
import AppKit
import EnvPeekKit

/// EnvPeek's screen: search environment variables, see where they come from, inspect PATH entry by entry.
struct EnvPeekView: View {
    @EnvironmentObject private var store: EnvStore

    var body: some View {
        VStack(spacing: 0) {
            controls
            Divider()
            sourceNote
            content
            Divider()
            footer
        }
    }

    private var controls: some View {
        VStack(spacing: 8) {
            Picker("Source", selection: Binding(get: { store.mode }, set: { store.setMode($0) })) {
                ForEach(EnvStore.Mode.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .accessibilityLabel("Environment source")

            if store.mode == .process {
                HStack(spacing: 6) {
                    TextField("Process ID (PID)", text: $store.pidText)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit { store.inspectProcess() }
                        .accessibilityLabel("Process ID")
                    Button("Inspect") { store.inspectProcess() }
                }
                .controlSize(.small)
            }
            SearchField(text: $store.query, prompt: "Search names and values…")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    @ViewBuilder private var sourceNote: some View {
        if let caveat = store.source.caveat, store.error == nil {
            Label(caveat, systemImage: "info.circle")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.accentColor.opacity(0.08))
        }
    }

    @ViewBuilder private var content: some View {
        if let error = store.error {
            EmptyState(symbol: "lock.slash", title: "Can't read that environment", message: error)
        } else if store.mode == .process && store.variables.isEmpty {
            EmptyState(symbol: "terminal", title: "Enter a PID to inspect",
                       message: "Only processes owned by your user can be read, and macOS hides the environment of protected system processes.")
        } else if store.visible.isEmpty {
            EmptyState(symbol: "magnifyingglass", title: "No matching variables")
        } else {
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(store.visible) { variable in
                        EnvRow(variable: variable)
                        Divider().opacity(0.4)
                    }
                }
            }
            .frame(maxHeight: .infinity)
        }
    }

    private var footer: some View {
        HStack {
            Text(store.source.label).lineLimit(1)
            Spacer()
            Text("Values stay on screen and are never logged")
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }
}

private struct EnvRow: View {
    @EnvironmentObject private var store: EnvStore
    let variable: EnvVariable

    private var isPath: Bool { PathAnalyzer.isPathLike(variable.name) }
    private var pathExpanded: Bool { store.expandedPathVariable == variable.name }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .top, spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(variable.name).font(.system(size: 12, weight: .semibold, design: .monospaced))
                    valueView
                }
                Spacer(minLength: 4)
                if isPath {
                    Button {
                        withAnimation(.easeOut(duration: 0.15)) { store.expandedPathVariable = pathExpanded ? nil : variable.name }
                    } label: {
                        Image(systemName: "list.number")
                    }
                    .buttonStyle(.borderless)
                    .help("Show entry by entry")
                    .accessibilityLabel("Show \(variable.name) entry by entry")
                }
                Menu {
                    Button("Copy name") { copy(variable.name) }
                    Button("Copy value") { copy(variable.value) }
                    Button("Copy NAME=value") { copy(variable.assignment) }
                } label: {
                    Image(systemName: "doc.on.doc")
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .help("Copy")
                .accessibilityLabel("Copy \(variable.name)")
            }
            if isPath && pathExpanded && store.isRevealed(variable) { PathEntries(value: variable.value) }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
    }

    @ViewBuilder private var valueView: some View {
        if store.isRevealed(variable) {
            Text(variable.value.isEmpty ? "(empty)" : variable.value)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.secondary)
                .lineLimit(pathExpanded ? 1 : 3)
                .textSelection(.enabled)
        } else {
            HStack(spacing: 6) {
                Text("••••••••").font(.system(size: 11, design: .monospaced)).foregroundStyle(.secondary)
                Button("Reveal") { store.toggleReveal(variable.name) }
                    .buttonStyle(.link).font(.caption)
                StatusBadge(text: "Looks sensitive", tone: .warning)
            }
        }
    }

    private func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}

private struct PathEntries: View {
    let value: String

    var body: some View {
        let entries = PathAnalyzer.analyze(value, directoryExists: Self.isDirectory)
        VStack(alignment: .leading, spacing: 3) {
            ForEach(entries) { entry in
                HStack(alignment: .top, spacing: 6) {
                    Text("\(entry.index + 1)").font(.caption2.monospacedDigit()).foregroundStyle(.tertiary).frame(width: 18, alignment: .trailing)
                    VStack(alignment: .leading, spacing: 0) {
                        Text(entry.path.isEmpty ? "(empty)" : entry.path).font(.system(size: 11, design: .monospaced)).lineLimit(2)
                        if !entry.notes.isEmpty {
                            Text(entry.notes.joined(separator: " · ")).font(.caption2).foregroundStyle(.orange)
                        }
                    }
                }
                .accessibilityElement(children: .combine)
            }
        }
        .padding(.leading, 4)
    }

    private static func isDirectory(_ path: String) -> Bool {
        var isDir: ObjCBool = false
        return FileManager.default.fileExists(atPath: (path as NSString).expandingTildeInPath, isDirectory: &isDir) && isDir.boolValue
    }
}
#endif
