#if os(macOS)
import SwiftUI
import ProcessPeekKit
import PortPeekKit

/// ProcessPeek's screen: a searchable process list; open a row for its identity and relationships.
struct ProcessPeekView: View {
    @EnvironmentObject private var store: ProcessStore

    var body: some View {
        VStack(spacing: 0) {
            searchBar
            Divider()
            content
            Divider()
            footer
        }
    }

    private var searchBar: some View {
        HStack(spacing: 6) {
            SearchField(text: $store.query, prompt: "Name, PID, user or path…")
            Menu {
                Picker("Sort by", selection: $store.sort) {
                    ForEach(ProcessSort.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                Toggle("Include other users' processes", isOn: $store.showAllUsers)
            } label: {
                Image(systemName: "line.3.horizontal.decrease.circle")
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .help("Sort and filter")
            .accessibilityLabel("Sort and filter")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    @ViewBuilder private var content: some View {
        if let error = store.error, store.snapshot == nil {
            ErrorState(message: error, retryTitle: "Try again") { store.refresh() }
        } else if store.snapshot == nil {
            VStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Reading processes…").font(.caption).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if store.visible.isEmpty {
            EmptyState(symbol: "magnifyingglass", title: "No matching processes",
                       message: store.showAllUsers ? nil : "Only your own processes are listed. Use the filter menu to include other users'.")
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(store.visible) { entry in
                            ProcessRow(entry: entry).id(entry.pid)
                            Divider().opacity(0.4)
                        }
                    }
                }
                .onChange(of: store.scrollTarget) { target in
                    guard let target else { return }
                    withAnimation { proxy.scrollTo(target, anchor: .top) }
                    store.scrolled()
                }
            }
            .frame(maxHeight: .infinity)
        }
    }

    private var footer: some View {
        HStack {
            if store.snapshot != nil {
                let n = store.visible.count
                Text("\(n) process\(n == 1 ? "" : "es")\(store.showAllUsers ? "" : " (yours)")")
            } else {
                Text("Reads when you open it")
            }
            Spacer()
            if store.isLoading { ProgressView().controlSize(.small) }
            Button { store.refresh() } label: { Image(systemName: "arrow.clockwise") }
                .buttonStyle(.borderless)
                .help("Read again")
                .keyboardShortcut("r", modifiers: .command)
                .accessibilityLabel("Read processes again")
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }
}

private struct ProcessRow: View {
    @EnvironmentObject private var store: ProcessStore
    let entry: ProcessEntry

    private var expanded: Bool { store.selectedPID == entry.pid }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(entry.name).font(.system(size: 13, weight: .medium)).lineLimit(1)
                    Text("PID \(entry.pid) · \(entry.user)").font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer(minLength: 4)
                if store.isOwned(entry) { StatusBadge(text: "You", tone: .info) }
                StatusBadge(text: entry.memoryLabel)
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.tertiary)
                    .rotationEffect(.degrees(expanded ? 90 : 0))
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .contentShape(Rectangle())
            .onTapGesture { withAnimation(.easeOut(duration: 0.15)) { store.toggle(entry.pid) } }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isButton)

            if expanded { ProcessDetailView(entry: entry) }
        }
        .background(expanded ? Color.accentColor.opacity(0.08) : .clear)
    }
}

private struct ProcessDetailView: View {
    @EnvironmentObject private var store: ProcessStore
    let entry: ProcessEntry

    private var rows: [(label: String, value: String)] {
        var rows: [(label: String, value: String)] = [
            ("PID", String(entry.pid)),
            ("User", "\(entry.user) (uid \(entry.uid))"),
            ("State", entry.stateLabel),
            ("Running for", entry.elapsedLabel),
            ("CPU", String(format: "%.1f%% (ps average)", entry.cpuPercent)),
            ("Memory", entry.memoryLabel + " resident"),
        ]
        if let started = entry.startTime { rows.insert(("Started", started.formatted(date: .abbreviated, time: .standard)), at: 3) }
        return rows
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            KeyValueRows(rows: rows)
            relation
            pathRow
            commandLine
            ports
            children
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 10)
    }

    @ViewBuilder private var relation: some View {
        if let snapshot = store.snapshot {
            let chain = snapshot.ancestors(of: entry)
            if let parent = chain.first {
                HStack(spacing: 4) {
                    Text("Parent").font(.caption).foregroundStyle(.secondary)
                    Button("\(parent.name) (PID \(parent.pid))") { store.jump(to: parent.pid) }
                        .buttonStyle(.link)
                }
                .font(.caption)
            } else {
                Text("No parent process (PID \(entry.ppid))").font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private var pathRow: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text("Executable").font(.caption).foregroundStyle(.secondary)
                CopyButton(text: entry.executable, label: "Copy executable path")
            }
            Text(entry.executable).font(.caption.monospaced()).textSelection(.enabled).lineLimit(3)
        }
    }

    @ViewBuilder private var commandLine: some View {
        VStack(alignment: .leading, spacing: 2) {
            if store.detailsLoading {
                HStack(spacing: 6) { ProgressView().controlSize(.small); Text("Reading details…").font(.caption).foregroundStyle(.secondary) }
            } else if let details = store.details, details.pid == entry.pid {
                HStack {
                    Text("Command line").font(.caption).foregroundStyle(.secondary)
                    if let line = details.commandLine { CopyButton(text: line, label: "Copy command line") }
                }
                if let line = details.commandLine {
                    Text(line).font(.caption.monospaced()).textSelection(.enabled).lineLimit(6)
                    Text("Command lines can contain secrets passed as arguments. It is shown here only and never logged.")
                        .font(.caption2).foregroundStyle(.tertiary)
                } else {
                    Text("Not available (the process may have exited).").font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }

    @ViewBuilder private var ports: some View {
        if let details = store.details, details.pid == entry.pid {
            VStack(alignment: .leading, spacing: 2) {
                Text("Listening ports").font(.caption).foregroundStyle(.secondary)
                if details.listeningPorts.isEmpty {
                    Text(details.portsNote ?? "None").font(.caption)
                } else {
                    ForEach(details.listeningPorts) { port in
                        Text("\(port.protocolType.rawValue) \(port.endpoint)").font(.caption.monospaced())
                    }
                }
            }
        }
    }

    @ViewBuilder private var children: some View {
        if let snapshot = store.snapshot {
            let kids = snapshot.children(of: entry.pid)
            if !kids.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Children (\(kids.count))").font(.caption).foregroundStyle(.secondary)
                    ForEach(kids.prefix(12)) { child in
                        Button("\(child.name) (PID \(child.pid))") { store.jump(to: child.pid) }
                            .buttonStyle(.link).font(.caption)
                    }
                    if kids.count > 12 { Text("and \(kids.count - 12) more").font(.caption2).foregroundStyle(.tertiary) }
                }
            }
        }
    }
}
#endif
