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
            footer
        }
        .background(PeekTheme.ground)
    }

    @ViewBuilder private var content: some View {
        if let error = store.error, store.snapshot == nil {
            ErrorState(message: error, retryTitle: "Try again") { store.startSampling() }
        } else if store.isWaitingForSecondSample {
            VStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Taking a first sample…").font(.caption).foregroundStyle(PeekTheme.muted)
                Text("CPU use appears after the second sample, a couple of seconds from now.")
                    .font(.caption2).foregroundStyle(PeekTheme.muted)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let usage = store.usage {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    RingsRow(usage: usage)
                    HistorySection(usage: usage)
                    DetailsSection(usage: usage)
                    LoadSection()
                    ProcessesSection()
                }
                .padding(14)
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
        .font(.system(size: 11))
        .foregroundStyle(PeekTheme.muted)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14)
        .padding(.vertical, 7)
        .overlay(alignment: .top) { Rectangle().fill(PeekTheme.border).frame(height: 1) }
    }
}

/// Thermal state, overall use (apps and macOS), and the load average against the number of cores.
private struct RingsRow: View {
    @EnvironmentObject private var store: CPUStore
    let usage: CPUUsage

    private var thermal: (fraction: Double, color: Color, label: String) {
        switch store.snapshot?.thermal {
        case .nominal: return (0.25, PeekTheme.green, "Normal")
        case .fair: return (0.5, PeekTheme.amber, "Raised")
        case .serious: return (0.75, PeekTheme.red, "High")
        case .critical: return (1, PeekTheme.red, "Critical")
        case nil: return (0, PeekTheme.muted, "Not reported")
        }
    }

    private var cores: Int { max(store.topology?.logicalCores ?? usage.perCore.count, 1) }
    private var load: Double? { store.snapshot?.loadAverage.first }

    var body: some View {
        VStack(spacing: 10) {
            HStack(alignment: .center) {
                VStack(spacing: 4) {
                    RingGauge(fraction: thermal.fraction, color: thermal.color, lineWidth: 6) {
                        Image(systemName: "thermometer.medium")
                            .font(.system(size: 17, weight: .medium))
                            .foregroundStyle(thermal.color)
                    }
                    .frame(width: 66, height: 66)
                    Text(thermal.label).font(.system(size: 12, weight: .medium))
                    Text("Thermal state").font(.system(size: 10.5)).foregroundStyle(PeekTheme.muted)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Thermal state, \(thermal.label)")
                Spacer()
                RingGauge(segments: [RingSegment(fraction: usage.user, color: PeekTheme.accent),
                                     RingSegment(fraction: usage.system, color: PeekTheme.red)], lineWidth: 9) {
                    VStack(spacing: 0) {
                        Text(PercentText.fraction(usage.total).replacingOccurrences(of: " ", with: ""))
                            .font(.system(size: 24, weight: .semibold)).monospacedDigit()
                        Text("in use").font(.system(size: 10.5)).foregroundStyle(PeekTheme.muted)
                    }
                }
                .frame(width: 104, height: 104)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("CPU in use, \(PercentText.fraction(usage.total))")
                Spacer()
                VStack(spacing: 4) {
                    RingGauge(fraction: (load ?? 0) / Double(cores), color: PeekTheme.accent, lineWidth: 6) {
                        Text(load.map { String(format: "%.2f", $0) } ?? "–")
                            .font(.system(size: 14, weight: .semibold)).monospacedDigit()
                    }
                    .frame(width: 66, height: 66)
                    Text("Load").font(.system(size: 12, weight: .medium))
                    Text("of \(cores) cores").font(.system(size: 10.5)).foregroundStyle(PeekTheme.muted)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Load average \(load.map { String(format: "%.2f", $0) } ?? "not reported") on \(cores) cores")
            }
            .padding(.horizontal, 8)
            HStack(spacing: 6) {
                Text(store.headline ?? "").font(.system(size: 13, weight: .semibold)).lineLimit(2)
                SampledPill()
            }
        }
    }
}

private struct HistorySection: View {
    @EnvironmentObject private var store: CPUStore
    let usage: CPUUsage

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel(text: "Usage since opened")
            VStack(alignment: .leading, spacing: 6) {
                HistoryChart(series: [.init(values: store.history.values, color: PeekTheme.accent)], maximum: 1)
                    .frame(height: 64)
                HStack(alignment: .bottom, spacing: 3) {
                    ForEach(Array(usage.perCore.enumerated()), id: \.offset) { _, value in
                        GeometryReader { proxy in
                            VStack(spacing: 0) {
                                Spacer(minLength: 0)
                                Rectangle()
                                    .fill(value > 0.85 ? PeekTheme.amber : PeekTheme.accent)
                                    .frame(height: proxy.size.height * CGFloat(min(max(value, 0), 1)))
                            }
                            .background(PeekTheme.track)
                            .clipShape(RoundedRectangle(cornerRadius: 3))
                        }
                    }
                }
                .frame(height: 34)
                .accessibilityElement()
                .accessibilityLabel("Use per core")
                .accessibilityValue(usage.perCore.map(PercentText.fraction).joined(separator: ", "))
                Text("One bar per core, latest sample")
                    .font(.system(size: 10.5)).foregroundStyle(PeekTheme.muted)
            }
            .themedCard(radius: 10, padding: 8)
        }
    }
}

private struct DetailsSection: View {
    @EnvironmentObject private var store: CPUStore
    let usage: CPUUsage

    private var uptime: String {
        let seconds = Int(ProcessInfo.processInfo.systemUptime)
        let days = seconds / 86_400, hours = (seconds % 86_400) / 3_600, minutes = (seconds % 3_600) / 60
        return days > 0 ? "\(days) d \(hours) h" : "\(hours) h \(minutes) min"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionLabel(text: "Details")
            DetailRow(label: "User (apps)", value: PercentText.fraction(usage.user), dot: PeekTheme.accent)
            DetailRow(label: "System (macOS)", value: PercentText.fraction(usage.system), dot: PeekTheme.red)
            DetailRow(label: "Idle", value: PercentText.fraction(1 - usage.total), dot: PeekTheme.freeSegment)
            if let topology = store.topology {
                if let chip = topology.chip { DetailRow(label: "Chip", value: chip) }
                DetailRow(label: "Cores", value: topology.coresLabel)
            }
            DetailRow(label: "Uptime", value: uptime)
        }
    }
}

private struct LoadSection: View {
    @EnvironmentObject private var store: CPUStore

    var body: some View {
        if let load = store.snapshot?.loadAverage, load.count == 3 {
            VStack(alignment: .leading, spacing: 6) {
                SectionLabel(text: "Average load")
                HStack(spacing: 8) {
                    ForEach(Array(zip(["1 min", "5 min", "15 min"], load).enumerated()), id: \.offset) { _, item in
                        VStack(alignment: .leading, spacing: 1) {
                            Text(item.0).font(.system(size: 11)).foregroundStyle(PeekTheme.muted)
                            Text(String(format: "%.2f", item.1)).font(.system(size: 14, weight: .medium, design: .monospaced))
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .themedCard(radius: 9, padding: 9)
                        .accessibilityElement(children: .combine)
                    }
                }
            }
        }
    }
}

private struct ProcessesSection: View {
    @EnvironmentObject private var store: CPUStore

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            SectionLabel(text: "Using the most CPU", trailing: "% of one core")
            if let error = store.processError {
                Text("Processes could not be read: \(error)").font(.caption).foregroundStyle(PeekTheme.warningText)
            } else if store.isMeasuringProcesses {
                Text("Measuring… the busiest processes appear after the next sample.").font(.caption).foregroundStyle(PeekTheme.muted)
            } else if store.processes.isEmpty {
                Text("None of your processes used the CPU during the last interval.").font(.caption).foregroundStyle(PeekTheme.muted)
            } else {
                ForEach(store.processes) { row in
                    HStack(spacing: 8) {
                        Text(row.name).lineLimit(1)
                        Spacer(minLength: 4)
                        Text(PercentText.ofOneCore(row.percent)).font(.system(size: 12.5, design: .monospaced))
                    }
                    .font(.system(size: 13))
                    .padding(.vertical, 3)
                    .overlay(alignment: .bottom) { Rectangle().fill(PeekTheme.hairline).frame(height: 1) }
                    .help("PID \(row.pid)")
                    .accessibilityElement(children: .combine)
                }
                Text("100 % is one core fully busy, as in Activity Monitor, so a busy app can show more than 100 %.")
                    .font(.system(size: 10.5)).foregroundStyle(PeekTheme.muted).padding(.top, 2)
            }
        }
    }
}
#endif
