#if os(macOS)
import SwiftUI
import SleepPeekKit

/// SleepPeek's screen: what is keeping the Mac awake, with verified facts kept apart from inference,
/// then (on request) recent sleep and wake events.
struct SleepPeekView: View {
    @EnvironmentObject private var store: SleepStore

    var body: some View {
        VStack(spacing: 0) {
            content
            Divider()
            footer
        }
    }

    @ViewBuilder private var content: some View {
        if let error = store.error, store.snapshot == nil {
            ErrorState(message: error, retryTitle: "Try again") { Task { await store.refresh() } }
        } else if let snapshot = store.snapshot {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    SummaryCard(snapshot: snapshot)
                    ForEach(snapshot.diagnosis.blockers) { blocker in BlockerCard(blocker: blocker) }
                    OtherAssertions(snapshot: snapshot)
                    HistorySection()
                }
                .padding(12)
            }
            .frame(maxHeight: .infinity)
        } else {
            VStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Reading power assertions…").font(.caption).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var footer: some View {
        HStack {
            Text("Read-only · never changes power settings")
            Spacer()
            Button { Task { await store.refresh() } } label: { Image(systemName: "arrow.clockwise") }
                .buttonStyle(.borderless)
                .help("Refresh now")
                .keyboardShortcut("r", modifiers: .command)
                .accessibilityLabel("Refresh sleep information")
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }
}

private struct SummaryCard: View {
    let snapshot: SleepSnapshot

    private var diagnosis: SleepDiagnosis { snapshot.diagnosis }
    private var symbol: String {
        diagnosis.systemSleepBlocked ? "exclamationmark.circle" : (diagnosis.displaySleepBlocked || diagnosis.userActive) ? "sun.max" : "moon.zzz"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                IconTile(symbol: symbol)
                Text(diagnosis.headline).font(.system(size: 13, weight: .semibold))
                Spacer(minLength: 4)
                CopyButton(text: diagnosis.copyText, label: "Copy sleep diagnosis")
            }
            if !diagnosis.macOSReportedBlockers.isEmpty {
                Label("macOS reports sleep is prevented by \(diagnosis.macOSReportedBlockers.joined(separator: ", "))",
                      systemImage: "checkmark.seal")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if diagnosis.userActive {
                Label("Recent keyboard or mouse activity also keeps the Mac awake.", systemImage: "cursorarrow.motionlines")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            let timers = timerRows
            if !timers.isEmpty { KeyValueRows(rows: timers) }
        }
        .peekCard()
    }

    private var timerRows: [(label: String, value: String)] {
        var rows: [(label: String, value: String)] = []
        if let minutes = snapshot.settings?.displaySleepMinutes { rows.append(("Display sleeps after", Self.minutes(minutes))) }
        if let minutes = snapshot.settings?.sleepMinutes { rows.append(("System sleeps after", Self.minutes(minutes))) }
        return rows
    }

    private static func minutes(_ value: Int) -> String {
        value == 0 ? "Never" : "\(value) min of inactivity"
    }
}

private struct BlockerCard: View {
    let blocker: SleepBlocker

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text(blocker.assertion.processName).font(.system(size: 13, weight: .medium))
                Text("PID \(blocker.assertion.pid)").font(.caption).foregroundStyle(.secondary)
                Spacer(minLength: 4)
                StatusBadge(text: blocker.assertion.preventsSystemSleep ? "Keeps Mac awake" : "Keeps display awake",
                            tone: .warning)
            }
            ForEach(Array(blocker.findings.enumerated()), id: \.offset) { _, finding in
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: finding.basis == .verified ? "checkmark.seal" : "lightbulb")
                        .font(.caption)
                        .foregroundStyle(finding.basis == .verified ? Color.green : Color.orange)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 0) {
                        Text(finding.basis == .verified ? "Reported by macOS" : "Likely (inference)")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Text(finding.text).font(.caption).textSelection(.enabled)
                    }
                }
                .accessibilityElement(children: .combine)
            }
        }
        .peekCard()
    }
}

/// Assertions that do not block sleep (like user activity) and kernel assertions, collapsed by default.
private struct OtherAssertions: View {
    let snapshot: SleepSnapshot

    var body: some View {
        let others = snapshot.report.assertions.filter { !$0.blocksSleep }
        let kernel = snapshot.report.kernelAssertions
        if !others.isEmpty || !kernel.isEmpty {
            DisclosureGroup("Other assertions (\(others.count + kernel.count))") {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(others) { assertion in
                        Text("\(assertion.processName) · \(assertion.type): \(assertion.name)")
                            .font(.caption).lineLimit(2).textSelection(.enabled)
                    }
                    ForEach(kernel) { assertion in
                        Text("Kernel · \(assertion.owner.isEmpty ? assertion.description : assertion.owner)")
                            .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 4)
            }
            .font(.caption)
        }
    }
}

private struct HistorySection: View {
    @EnvironmentObject private var store: SleepStore

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Recent sleep and wake events").font(.caption.weight(.semibold))
            switch store.history {
            case .idle:
                VStack(alignment: .leading, spacing: 6) {
                    Text("Read from the system power log. This can take up to a minute, so it only loads when you ask.")
                        .font(.caption).foregroundStyle(.secondary)
                    Button("Load history") { store.loadHistory() }
                }
            case .loading:
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Reading the power log…").font(.caption).foregroundStyle(.secondary)
                }
            case .failed(let message):
                VStack(alignment: .leading, spacing: 6) {
                    Text(message).font(.caption).foregroundStyle(.secondary)
                    Button("Try again") { store.loadHistory() }
                }
            case .loaded(let history):
                HistoryList(history: history)
            }
        }
        .peekCard()
    }
}

private struct HistoryList: View {
    @EnvironmentObject private var store: SleepStore
    let history: SleepHistory

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if history.events.isEmpty {
                Text("The power log has no sleep or wake events.").font(.caption).foregroundStyle(.secondary)
            } else {
                Text("\(history.events.count) most recent: \(history.count(of: .sleep)) sleeps, \(history.count(of: .darkWake)) background wakes (display stayed off), \(history.count(of: .wake)) full wakes")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if !history.wakeRequests.isEmpty {
                Text("Scheduled wake requests when the log last recorded them").font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
                ForEach(history.wakeRequests) { request in
                    VStack(alignment: .leading, spacing: 0) {
                        Text("\(request.process) · \(request.request)").font(.caption)
                        Text(Self.detail(of: request))
                            .font(.caption2).foregroundStyle(.secondary).lineLimit(2)
                    }
                }
            }
            Divider().opacity(0.5)
            ForEach(history.events) { event in
                HStack(alignment: .top, spacing: 8) {
                    Text(Self.time(event.date)).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                        .frame(width: 118, alignment: .leading)
                    VStack(alignment: .leading, spacing: 1) {
                        HStack(spacing: 4) {
                            StatusBadge(text: event.kind.rawValue, tone: event.kind == .sleep ? .neutral : .info)
                            if let source = event.powerSource { Text(source).font(.caption2).foregroundStyle(.secondary) }
                        }
                        if let reason = event.reason {
                            Text(reason).font(.caption2).foregroundStyle(.secondary).lineLimit(2).textSelection(.enabled)
                        }
                    }
                    Spacer(minLength: 0)
                }
            }
            Button("Reload") { store.loadHistory() }.controlSize(.small)
        }
    }

    private static func detail(of request: WakeRequest) -> String {
        let when = request.wakeAt.map(time) ?? "time unknown"
        return request.info.isEmpty ? when : when + " · " + request.info
    }

    private static func time(_ date: Date) -> String {
        date.formatted(date: .abbreviated, time: .standard)
    }
}
#endif
