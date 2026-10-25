#if os(macOS)
import SwiftUI
import MacPeekCore
import MemoryPeekKit

/// MemoryPeek's screen: whether the Mac is short of RAM, how memory is split, and the processes using the most.
struct MemoryPeekView: View {
    @EnvironmentObject private var store: MemoryStore

    var body: some View {
        VStack(spacing: 0) {
            content
            Divider()
            footer
        }
    }

    @ViewBuilder private var content: some View {
        if let error = store.error, store.stats == nil {
            ErrorState(message: error, retryTitle: "Try again") { store.startPolling() }
        } else if let stats = store.stats, let breakdown = store.breakdown, let assessment = store.assessment {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    PressureCard(stats: stats, assessment: assessment)
                    BreakdownCard(stats: stats, breakdown: breakdown)
                    TopProcessesCard()
                }
                .padding(12)
            }
            .frame(maxHeight: .infinity)
        } else {
            VStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Reading memory…").font(.caption).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Read every \(Int(store.interval)) s while this screen is open. Reading stops when you leave it.")
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

private struct PressureCard: View {
    let stats: MemoryStats
    let assessment: MemoryAssessment

    private var badge: (text: String, tone: StatusBadge.Tone) {
        switch stats.pressure {
        case .normal: return ("Pressure: Normal", .good)
        case .warning: return ("Pressure: Warning", .warning)
        case .critical: return ("Pressure: Critical", .warning)
        case nil: return ("Pressure: Not reported", .neutral)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                IconTile(symbol: "memorychip")
                Text(assessment.headline).font(.system(size: 13, weight: .semibold)).lineLimit(2)
                Spacer(minLength: 4)
                StatusBadge(text: badge.text, tone: badge.tone)
            }
            ForEach(Array(assessment.detail.enumerated()), id: \.offset) { _, line in
                Text(line).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
        .peekCard()
    }
}

private struct BreakdownCard: View {
    let stats: MemoryStats
    let breakdown: MemoryBreakdown

    private struct Segment: Identifiable {
        let id: String
        let bytes: UInt64
        let color: Color
    }

    private var segments: [Segment] {
        [Segment(id: "App memory", bytes: breakdown.app, color: .blue),
         Segment(id: "Wired", bytes: breakdown.wired, color: .orange),
         Segment(id: "Compressed", bytes: breakdown.compressed, color: .purple),
         Segment(id: "Cached files", bytes: breakdown.cachedFiles, color: .teal),
         Segment(id: "Free", bytes: breakdown.free, color: Color.primary.opacity(0.08))]
    }

    private var rows: [(label: String, value: String)] {
        var rows: [(label: String, value: String)] = [
            ("Installed", ByteCountText.memory(breakdown.physical)),
            ("Used", ByteCountText.memory(breakdown.used)),
            ("  App memory", ByteCountText.memory(breakdown.app)),
            ("  Wired (kept by macOS)", ByteCountText.memory(breakdown.wired)),
            ("  Compressed", ByteCountText.memory(breakdown.compressed)),
            ("Cached files", ByteCountText.memory(breakdown.cachedFiles) + " (reused when apps need it)"),
            ("Free", ByteCountText.memory(breakdown.free)),
        ]
        if let used = stats.swapUsedBytes {
            rows.append(("Moved to disk (swap)", ByteCountText.memory(used)))
        } else {
            rows.append(("Moved to disk (swap)", "Not reported"))
        }
        return rows
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("How memory is used").font(.caption.weight(.semibold))
            GeometryReader { proxy in
                HStack(spacing: 1) {
                    ForEach(segments) { segment in
                        Rectangle()
                            .fill(segment.color)
                            .frame(width: width(of: segment.bytes, in: proxy.size.width))
                    }
                }
            }
            .frame(height: 10)
            .clipShape(Capsule())
            .accessibilityHidden(true)
            HStack(spacing: 10) {
                ForEach(segments.dropLast()) { segment in
                    HStack(spacing: 3) {
                        Circle().fill(segment.color).frame(width: 7, height: 7)
                        Text(segment.id)
                    }
                }
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
            .accessibilityHidden(true)
            KeyValueRows(rows: rows)
        }
        .peekCard()
    }

    private func width(of bytes: UInt64, in total: CGFloat) -> CGFloat {
        guard breakdown.physical > 0 else { return 0 }
        let gaps = CGFloat(segments.count - 1)
        return max(total - gaps, 0) * CGFloat(Double(bytes) / Double(breakdown.physical))
    }
}

private struct TopProcessesCard: View {
    @EnvironmentObject private var store: MemoryStore

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Using the most memory").font(.caption.weight(.semibold))
            if let error = store.processError {
                Text("Processes could not be read: \(error)").font(.caption).foregroundStyle(.orange)
            } else if store.topProcesses.isEmpty {
                Text("No processes could be read.").font(.caption).foregroundStyle(.secondary)
            } else {
                ForEach(store.topProcesses) { row in
                    HStack(spacing: 8) {
                        VStack(alignment: .leading, spacing: 0) {
                            Text(row.name).font(.system(size: 12, weight: .medium)).lineLimit(1)
                            Text("PID \(row.pid)").font(.caption2).foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 4)
                        Text(ByteCountText.memory(row.footprintBytes)).font(.caption.monospacedDigit())
                    }
                    .accessibilityElement(children: .combine)
                }
                Text("Memory footprint, the figure Activity Monitor's Memory column shows.")
                    .font(.caption2).foregroundStyle(.tertiary)
            }
        }
        .peekCard()
    }
}
#endif
