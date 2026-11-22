#if os(macOS)
import SwiftUI
import MacPeekCore
import VitalsKit

/// The last 1, 6 or 24 hours of CPU, memory, network, GPU, temperature and power, from the history MacPeek keeps on this
/// Mac. "What's normal for this Mac?" is easier to answer from a day than from a minute.
struct HistoryView: View {
    @EnvironmentObject private var router: UtilityRouter
    @EnvironmentObject private var monitor: VitalsMonitor
    @EnvironmentObject private var settings: AppSettings
    @State private var hours = 1

    private var points: [VitalsPoint] {
        monitor.history.points(since: Date().addingTimeInterval(-Double(hours) * 3600), maximumCount: 240)
    }

    var body: some View {
        VStack(spacing: 0) {
            PeekHeader(title: "History", subtitle: "Kept on this Mac", onBack: { router.back() })
            Divider()
            if !settings.historyEnabled {
                EmptyState(symbol: "chart.xyaxis.line", title: "History is off",
                           message: "Turn it on to keep 24 hours of CPU, memory, network, GPU and temperature readings on this Mac.",
                           actionTitle: "Turn on history", action: { settings.historyEnabled = true })
            } else if points.count < 2 {
                EmptyState(symbol: "hourglass", title: "Collecting…",
                           message: "MacPeek adds a point every 10 seconds. Charts appear after the first minute.")
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        Picker("Range", selection: $hours) {
                            Text("1 hour").tag(1)
                            Text("6 hours").tag(6)
                            Text("24 hours").tag(24)
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                        let points = self.points
                        MetricChart(title: "CPU", points: points, metrics: [.cpu], maximum: 1, format: Self.percent)
                        MetricChart(title: "Memory used", points: points, metrics: [.memory], maximum: 1, format: Self.percent,
                                    note: Self.pressureNote(points))
                        MetricChart(title: "Network", points: points, metrics: [.networkIn, .networkOut], maximum: nil,
                                    format: { ByteCountText.binary($0) + "/s" }, legend: ["Download", "Upload"])
                        if points.contains(where: { $0.gpu != nil }) {
                            MetricChart(title: "GPU", points: points, metrics: [.gpu], maximum: 1, format: Self.percent)
                        }
                        if points.contains(where: { $0.temperature != nil }) {
                            MetricChart(title: "Temperature", points: points, metrics: [.temperature], maximum: nil,
                                        format: { "\(Int($0.rounded())) °C" })
                        }
                        if points.contains(where: { $0.power != nil }) {
                            MetricChart(title: "Power", points: points, metrics: [.power], maximum: nil,
                                        format: { String(format: "%.1f W", $0) })
                        }
                        Text("Averages over each point. Values are read every 5 seconds while history is on and saved in ~/Library/Application Support/MacPeek. Nothing leaves this Mac unless a device of its MacPeek Remote account asks for it.")
                            .font(.system(size: 10.5)).foregroundStyle(PeekTheme.muted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(14)
                }
            }
        }
        .background(PeekTheme.ground)
    }

    static func percent(_ value: Double) -> String { "\(Int((value * 100).rounded()))%" }

    static func pressureNote(_ points: [VitalsPoint]) -> String? {
        if points.contains(where: { $0.pressure == .critical }) { return "Memory pressure was critical in this period." }
        if points.contains(where: { $0.pressure == .warning }) { return "Memory pressure was raised in this period." }
        return nil
    }
}

private struct MetricChart: View {
    let title: String
    let points: [VitalsPoint]
    let metrics: [VitalsMetric]
    /// A fixed scale (fractions), or nil to scale to the largest value.
    let maximum: Double?
    let format: (Double) -> String
    var legend: [String] = []
    var note: String? = nil

    private static let colors = [PeekTheme.accent, PeekTheme.teal]

    private func values(_ metric: VitalsMetric) -> [Double] { points.compactMap { $0.value(metric) } }
    private func times(_ metric: VitalsMetric) -> [Date] { points.compactMap { $0.value(metric) == nil ? nil : $0.time } }

    var body: some View {
        let all = metrics.flatMap(values)
        let peak = all.max() ?? 0
        let scale = maximum ?? max(peak * 1.15, 0.000_001)
        let average = all.isEmpty ? 0 : all.reduce(0, +) / Double(all.count)
        VStack(alignment: .leading, spacing: 6) {
            SectionLabel(text: title, trailing: "avg \(format(average)) · peak \(format(peak))")
            VStack(alignment: .leading, spacing: 4) {
                HistoryChart(series: metrics.enumerated().map { index, metric in
                    HistoryChart.Series(values: values(metric), color: Self.colors[index % Self.colors.count], filled: index == 0,
                                        times: times(metric), name: legend.indices.contains(index) ? legend[index] : nil)
                }, maximum: scale, format: format)
                .frame(height: 56)
                if !legend.isEmpty {
                    HStack(spacing: 10) {
                        ForEach(Array(legend.enumerated()), id: \.offset) { index, name in
                            HStack(spacing: 4) {
                                Circle().fill(Self.colors[index % Self.colors.count]).frame(width: 6, height: 6)
                                Text(name)
                            }
                        }
                    }
                    .font(.system(size: 10.5))
                    .foregroundStyle(PeekTheme.muted)
                }
                if let note {
                    Text(note).font(.system(size: 10.5)).foregroundStyle(PeekTheme.warningText)
                }
            }
            .themedCard(radius: 10, padding: 8)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title): average \(format(average)), peak \(format(peak))")
    }
}
#endif
