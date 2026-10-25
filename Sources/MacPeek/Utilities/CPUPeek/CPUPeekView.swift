#if os(macOS)
import SwiftUI
import CPUPeekKit

/// CPUPeek's screen: how busy the CPU is, whether macOS is holding it back to cool down, and which processes are
/// using it, sampled while this screen is open.
struct CPUPeekView: View {
    @EnvironmentObject private var store: CPUStore

    var body: some View {
        VStack(spacing: 0) {
            content
            Divider()
            footer
        }
    }

    @ViewBuilder private var content: some View {
        if let error = store.error, store.snapshot == nil {
            ErrorState(message: error, retryTitle: "Try again") { store.startSampling() }
        } else if store.isWaitingForSecondSample {
            VStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Taking a first sample…").font(.caption).foregroundStyle(.secondary)
                Text("CPU use appears after the second sample, a couple of seconds from now.")
                    .font(.caption2).foregroundStyle(.tertiary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if let usage = store.usage { OverviewCard(usage: usage) }
                    ProcessesCard()
                }
                .padding(12)
            }
            .frame(maxHeight: .infinity)
        }
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Sampled every \(Int(store.interval)) s while this screen is open. Sampling stops when you leave it.")
            if store.unreadableProcesses > 0 {
                Text("\(store.unreadableProcesses) processes (other users' or protected, including some macOS services) cannot be read and are not listed.")
            }
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }
}

private struct OverviewCard: View {
    @EnvironmentObject private var store: CPUStore
    let usage: CPUUsage

    private var rows: [(label: String, value: String)] {
        var rows: [(label: String, value: String)] = [
            ("In use", "\(PercentText.fraction(usage.total)) of all cores · \(PercentText.fraction(usage.user)) apps, \(PercentText.fraction(usage.system)) macOS"),
        ]
        if let topology = store.topology {
            if let chip = topology.chip { rows.append(("Chip", chip)) }
            rows.append(("Cores", topology.coresLabel))
        }
        if let load = store.snapshot?.loadAverage, load.count == 3 {
            rows.append(("Load average", String(format: "%.2f · %.2f · %.2f (1, 5, 15 min)", load[0], load[1], load[2])))
        }
        rows.append(("Temperature", store.snapshot?.thermal?.label ?? "Not reported"))
        return rows
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                IconTile(symbol: "speedometer")
                Text(store.headline ?? "").font(.system(size: 13, weight: .semibold)).lineLimit(2)
                Spacer(minLength: 4)
                if store.snapshot?.thermal?.isElevated == true {
                    StatusBadge(text: "Hot", tone: .warning)
                } else {
                    StatusBadge(text: "Sampled", tone: .info)
                }
            }
            CoreBars(perCore: usage.perCore)
            KeyValueRows(rows: rows)
        }
        .peekCard()
    }
}

/// One thin bar per logical core, filled to its use over the last interval.
private struct CoreBars: View {
    let perCore: [Double]

    var body: some View {
        HStack(alignment: .bottom, spacing: 2) {
            ForEach(Array(perCore.enumerated()), id: \.offset) { _, value in
                GeometryReader { proxy in
                    VStack(spacing: 0) {
                        Spacer(minLength: 0)
                        Rectangle()
                            .fill(value > 0.85 ? Color.orange : Color.accentColor)
                            .frame(height: proxy.size.height * min(max(value, 0), 1))
                    }
                    .background(Color.primary.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 2))
                }
            }
        }
        .frame(height: 28)
        .accessibilityElement()
        .accessibilityLabel("Use per core")
        .accessibilityValue(perCore.map(PercentText.fraction).joined(separator: ", "))
    }
}

private struct ProcessesCard: View {
    @EnvironmentObject private var store: CPUStore

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Using the most CPU").font(.caption.weight(.semibold))
            if let error = store.processError {
                Text("Processes could not be read: \(error)").font(.caption).foregroundStyle(.orange)
            } else if store.isMeasuringProcesses {
                Text("Measuring… the busiest processes appear after the next sample.").font(.caption).foregroundStyle(.secondary)
            } else if store.processes.isEmpty {
                Text("None of your processes used the CPU during the last interval.").font(.caption).foregroundStyle(.secondary)
            } else {
                ForEach(store.processes) { row in
                    HStack(spacing: 8) {
                        VStack(alignment: .leading, spacing: 0) {
                            Text(row.name).font(.system(size: 12, weight: .medium)).lineLimit(1)
                            Text("PID \(row.pid)").font(.caption2).foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 4)
                        Text(PercentText.ofOneCore(row.percent)).font(.caption.monospacedDigit())
                    }
                    .accessibilityElement(children: .combine)
                }
                Text("100 % is one core fully busy, as in Activity Monitor, so a busy app can show more than 100 %.")
                    .font(.caption2).foregroundStyle(.tertiary)
            }
        }
        .peekCard()
    }
}
#endif
