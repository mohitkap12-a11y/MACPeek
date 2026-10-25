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
        }
        .background(PeekTheme.ground)
    }

    @ViewBuilder private var content: some View {
        if let error = store.error, store.stats == nil {
            ErrorState(message: error, retryTitle: "Try again") { store.startPolling() }
        } else if let stats = store.stats, let breakdown = store.breakdown, let assessment = store.assessment {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    GaugesRow(stats: stats, breakdown: breakdown)
                    AssessmentNote(assessment: assessment)
                    VStack(alignment: .leading, spacing: 8) {
                        SectionLabel(text: "Used since opened")
                        HistoryChart(series: [.init(values: store.history.values, color: PeekTheme.accent)], maximum: 1)
                            .frame(height: 56)
                            .themedCard(radius: 10, padding: 8)
                    }
                    BreakdownSection(stats: stats, breakdown: breakdown)
                    TopProcessesSection()
                }
                .padding(14)
            }
            .frame(maxHeight: .infinity)
        } else {
            VStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Reading memory…").font(.caption).foregroundStyle(PeekTheme.muted)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

/// Memory colours, shared by the ring, the bar and the legend.
private enum MemoryColors {
    static let app = PeekTheme.accent
    static let wired = PeekTheme.amber
    static let compressed = PeekTheme.red
    static let cached = PeekTheme.teal
    static let free = PeekTheme.freeSegment
}

private struct GaugesRow: View {
    let stats: MemoryStats
    let breakdown: MemoryBreakdown

    private var pressure: (level: Double?, label: String, color: Color) {
        switch stats.pressure {
        case .normal: return (0.18, "Normal", PeekTheme.green)
        case .warning: return (0.5, "Warning", PeekTheme.warningText)
        case .critical: return (0.85, "Critical", PeekTheme.red)
        case nil: return (nil, "Not reported", PeekTheme.muted)
        }
    }

    private func share(_ bytes: UInt64) -> Double {
        breakdown.physical > 0 ? Double(bytes) / Double(breakdown.physical) : 0
    }

    var body: some View {
        HStack {
            Spacer()
            VStack(spacing: 2) {
                PressureGauge(level: pressure.level).frame(width: 132, height: 76)
                Text(pressure.label).font(.system(size: 14, weight: .semibold)).foregroundStyle(pressure.color)
                Text("Memory pressure").font(.system(size: 10.5)).foregroundStyle(PeekTheme.muted)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Memory pressure, \(pressure.label)")
            Spacer()
            RingGauge(segments: [RingSegment(fraction: share(breakdown.app), color: MemoryColors.app),
                                 RingSegment(fraction: share(breakdown.wired), color: MemoryColors.wired),
                                 RingSegment(fraction: share(breakdown.compressed), color: MemoryColors.compressed)],
                      lineWidth: 9) {
                VStack(spacing: 0) {
                    Text("\(Int((share(breakdown.used) * 100).rounded()))%")
                        .font(.system(size: 22, weight: .semibold)).monospacedDigit()
                    Text("used").font(.system(size: 10.5)).foregroundStyle(PeekTheme.muted)
                }
            }
            .frame(width: 100, height: 100)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(Int((share(breakdown.used) * 100).rounded())) percent of memory used")
            Spacer()
        }
    }
}

private struct AssessmentNote: View {
    let assessment: MemoryAssessment

    private var highlighted: Bool { assessment.tone == .warning || assessment.tone == .critical }

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(assessment.headline).font(.system(size: 12.5, weight: .semibold))
            ForEach(Array(assessment.detail.enumerated()), id: \.offset) { _, line in
                Text(line).foregroundStyle(PeekTheme.muted).fixedSize(horizontal: false, vertical: true)
            }
        }
        .font(.system(size: 12.5))
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(highlighted ? PeekTheme.noteBackground : PeekTheme.card, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(highlighted ? PeekTheme.noteBorder : PeekTheme.border))
        .accessibilityElement(children: .combine)
    }
}

private struct BreakdownSection: View {
    let stats: MemoryStats
    let breakdown: MemoryBreakdown

    private func share(_ bytes: UInt64) -> Double {
        breakdown.physical > 0 ? Double(bytes) / Double(breakdown.physical) : 0
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            SectionLabel(text: "How memory is used", trailing: "\(ByteCountText.memory(breakdown.physical)) installed")
            SegmentedBar(parts: [
                .init(fraction: share(breakdown.app), color: MemoryColors.app),
                .init(fraction: share(breakdown.wired), color: MemoryColors.wired),
                .init(fraction: share(breakdown.compressed), color: MemoryColors.compressed),
                .init(fraction: share(breakdown.cachedFiles), color: MemoryColors.cached),
                .init(fraction: share(breakdown.free), color: MemoryColors.free),
            ])
            DetailRow(label: "Used", value: ByteCountText.memory(breakdown.used))
            DetailRow(label: "App memory", value: ByteCountText.memory(breakdown.app), dot: MemoryColors.app)
            DetailRow(label: "Wired (kept by macOS)", value: ByteCountText.memory(breakdown.wired), dot: MemoryColors.wired)
            DetailRow(label: "Compressed", value: ByteCountText.memory(breakdown.compressed), dot: MemoryColors.compressed)
            DetailRow(label: "Cached files (reused when needed)", value: ByteCountText.memory(breakdown.cachedFiles), dot: MemoryColors.cached)
            DetailRow(label: "Free", value: ByteCountText.memory(breakdown.free), dot: MemoryColors.free)
            DetailRow(label: "Moved to disk (swap)", value: stats.swapUsedBytes.map(ByteCountText.memory) ?? "Not reported")
        }
    }
}

private struct TopProcessesSection: View {
    @EnvironmentObject private var store: MemoryStore

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            SectionLabel(text: "Using the most memory", trailing: "Footprint")
            if let error = store.processError {
                Text("Processes could not be read: \(error)").font(.caption).foregroundStyle(PeekTheme.warningText)
            } else if !store.hasReadProcesses {
                Text("Reading processes…").font(.caption).foregroundStyle(PeekTheme.muted)
            } else if store.topProcesses.isEmpty {
                Text("No processes could be read.").font(.caption).foregroundStyle(PeekTheme.muted)
            } else {
                ForEach(store.topProcesses) { row in
                    HStack(spacing: 8) {
                        Text(row.name).lineLimit(1)
                        Spacer(minLength: 4)
                        Text(ByteCountText.memory(row.footprintBytes)).font(.system(size: 12.5, design: .monospaced))
                    }
                    .font(.system(size: 13))
                    .padding(.vertical, 3)
                    .overlay(alignment: .bottom) { Rectangle().fill(PeekTheme.hairline).frame(height: 1) }
                    .help("PID \(row.pid)")
                    .accessibilityElement(children: .combine)
                }
                Text("Memory footprint, the figure Activity Monitor's Memory column shows.")
                    .font(.system(size: 10.5)).foregroundStyle(PeekTheme.muted).padding(.top, 2)
            }
        }
    }
}
#endif
