#if os(macOS)
import SwiftUI
import MacPeekCore
import GPUPeekKit

/// GPUPeek's screen, laid out like CPUPeek: rings for GPU memory, GPU busy and the Neural Engine, a chart since opened,
/// details, power and the processes using the GPU. Sampled while this screen is open.
struct GPUPeekView: View {
    @EnvironmentObject private var store: GPUStore
    /// Which GPU is shown on a Mac with more than one (an Intel Mac with two GPUs, or an external GPU).
    @State private var selectedID: String?

    var body: some View {
        VStack(spacing: 0) {
            if let error = store.error, store.snapshot != nil {
                BannerView(banner: Banner(kind: .error, text: "Couldn't refresh: \(error) Showing the last reading."))
            }
            content
        }
        .background(PeekTheme.ground)
    }

    private func selected(in snapshot: GPUSnapshot) -> GPUInfo? {
        snapshot.gpus.first { $0.id == selectedID } ?? snapshot.primary
    }

    /// Metal's facts for `gpu`: matched by name, so a second GPU never shows the first one's limits.
    private func facts(for gpu: GPUInfo, in snapshot: GPUSnapshot) -> GPUDeviceFacts? {
        guard let device = snapshot.device else { return nil }
        return device.name == gpu.name || (snapshot.gpus.count == 1) ? device : nil
    }

    @ViewBuilder private var content: some View {
        if let error = store.error, store.snapshot == nil {
            ErrorState(message: error, retryTitle: "Try again") { store.startSampling() }
        } else if let snapshot = store.snapshot {
            if let gpu = selected(in: snapshot) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        if snapshot.gpus.count > 1 { GPUPicker(gpus: snapshot.gpus, selectedID: $selectedID, current: gpu.id) }
                        GPURingsRow(gpu: gpu, snapshot: snapshot, facts: facts(for: gpu, in: snapshot))
                        GPUHistorySection(gpuID: gpu.id)
                        GPUDetailsSection(gpu: gpu, facts: facts(for: gpu, in: snapshot))
                        GPUPowerSection(snapshot: snapshot)
                        GPUProcessesSection(processes: snapshot.processes)
                    }
                    .padding(14)
                }
                .frame(maxHeight: .infinity)
            } else {
                EmptyState(symbol: "cpu", title: "macOS lists no GPU", message: "No IOAccelerator service was found.")
            }
        } else {
            VStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Reading the GPU…").font(.caption).foregroundStyle(PeekTheme.muted)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

/// A segmented choice between GPUs, shown only when macOS lists more than one.
private struct GPUPicker: View {
    let gpus: [GPUInfo]
    @Binding var selectedID: String?
    let current: String

    var body: some View {
        Picker("GPU", selection: Binding(get: { selectedID ?? current }, set: { selectedID = $0 })) {
            ForEach(gpus) { gpu in Text(gpu.name).tag(gpu.id) }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
    }
}

/// GPU memory (left), GPU busy (centre) and the Neural Engine (right), as CPUPeek shows thermal state, CPU and load.
private struct GPURingsRow: View {
    @EnvironmentObject private var store: GPUStore
    let gpu: GPUInfo
    let snapshot: GPUSnapshot
    let facts: GPUDeviceFacts?

    private var busyColor: Color {
        guard let utilization = gpu.deviceUtilization else { return PeekTheme.muted }
        if utilization >= GPUAssessment.alertUtilization { return PeekTheme.red }
        return utilization >= 70 ? PeekTheme.amber : PeekTheme.accent
    }

    private var memoryFraction: Double? { GPUAssessment.memoryFraction(gpu, facts: facts) }
    private var memoryValue: String {
        if let used = gpu.memoryInUseBytes ?? gpu.vramUsedBytes { return ByteCountText.memory(used) }
        return "–"
    }
    private var memoryCaption: String {
        if let limit = facts?.recommendedMaxWorkingSetBytes, gpu.memoryInUseBytes != nil {
            return "of \(ByteCountText.memory(limit))"
        }
        if let total = gpu.vramTotalBytes { return "of \(ByteCountText.memory(total)) VRAM" }
        return "in use"
    }

    private var aneWatts: Double? { snapshot.power?.neuralEngineWatts }
    private var aneFraction: Double {
        guard let watts = aneWatts, store.neuralEnginePeakWatts > 0 else { return 0 }
        return min(watts / store.neuralEnginePeakWatts, 1)
    }

    var body: some View {
        VStack(spacing: 10) {
            HStack(alignment: .center) {
                memoryRing
                Spacer()
                busyRing
                Spacer()
                aneRing
            }
            .padding(.horizontal, 8)
            HStack(spacing: 6) {
                Text(GPUAssessment.headline(gpu, power: snapshot.power)).font(.system(size: 13, weight: .semibold)).lineLimit(2)
                SampledPill()
            }
        }
    }

    private var memoryRing: some View {
        SideRing(fraction: memoryFraction ?? 0, color: PeekTheme.teal, value: memoryValue, title: "GPU memory", caption: memoryCaption)
            .accessibilityLabel("GPU memory, \(memoryValue) \(memoryCaption)")
    }

    private var busyText: String { gpu.deviceUtilization.map { "\(Int($0.rounded()))%" } ?? "–" }

    private var busyRing: some View {
        RingGauge(fraction: gpu.utilizationFraction ?? 0, color: busyColor, lineWidth: 9) {
            VStack(spacing: 0) {
                Text(busyText).font(.system(size: 24, weight: .semibold)).monospacedDigit()
                Text("busy").font(.system(size: 10.5)).foregroundStyle(PeekTheme.muted)
            }
        }
        .frame(width: 104, height: 104)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("GPU busy, \(busyText)")
    }

    private var aneValue: String { aneWatts.map(Watts.label) ?? "–" }
    private var aneCaption: String {
        guard snapshot.hasNeuralEngine else { return "not on Intel" }
        guard aneWatts != nil else { return "measuring" }
        return snapshot.power?.neuralEngineActive == true ? "working" : "idle"
    }

    private var aneRing: some View {
        SideRing(fraction: aneFraction, color: snapshot.hasNeuralEngine ? PeekTheme.accent : PeekTheme.muted,
                 value: aneValue, title: "Neural Engine", caption: aneCaption)
            .accessibilityLabel("Neural Engine, \(aneValue), \(aneCaption)")
    }
}

private struct SideRing: View {
    let fraction: Double
    let color: Color
    let value: String
    let title: String
    let caption: String

    var body: some View {
        VStack(spacing: 4) {
            RingGauge(fraction: fraction, color: color, lineWidth: 6) {
                Text(value).font(.system(size: 12.5, weight: .semibold)).monospacedDigit().minimumScaleFactor(0.7).lineLimit(1)
                    .padding(.horizontal, 6)
            }
            .frame(width: 66, height: 66)
            Text(title).font(.system(size: 12, weight: .medium))
            Text(caption).font(.system(size: 10.5)).foregroundStyle(PeekTheme.muted).lineLimit(1)
        }
        .frame(width: 92)
        .accessibilityElement(children: .ignore)
    }
}

private struct GPUHistorySection: View {
    @EnvironmentObject private var store: GPUStore
    let gpuID: String

    private var busy: [Double] { store.utilizationHistories[gpuID]?.values ?? [] }

    private var aneNormalized: [Double] {
        let peak = store.neuralEnginePeakWatts
        return peak > 0 ? store.neuralEngineHistory.values.map { $0 / peak * 100 } : []
    }

    var body: some View {
        if busy.count > 1 || aneNormalized.count > 1 {
            VStack(alignment: .leading, spacing: 8) {
                SectionLabel(text: "Since opened")
                VStack(alignment: .leading, spacing: 6) {
                    HistoryChart(series: [.init(values: busy, color: PeekTheme.accent),
                                          .init(values: aneNormalized, color: PeekTheme.teal, filled: false)],
                                 maximum: 100)
                        .frame(height: 64)
                    HStack(spacing: 12) {
                        HStack(spacing: 5) { LegendDot(color: PeekTheme.accent); Text("GPU busy") }
                        if !aneNormalized.isEmpty {
                            HStack(spacing: 5) { LegendDot(color: PeekTheme.teal); Text("Neural Engine, of its peak") }
                        }
                    }
                    .font(.system(size: 10.5)).foregroundStyle(PeekTheme.muted)
                }
                .themedCard(radius: 10, padding: 8)
            }
        }
    }
}

private struct GPUDetailsSection: View {
    let gpu: GPUInfo
    let facts: GPUDeviceFacts?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionLabel(text: "Details")
            if let renderer = gpu.rendererUtilization {
                DetailRow(label: "Renderer", value: "\(Int(renderer.rounded())) %", dot: PeekTheme.accent)
            }
            if let tiler = gpu.tilerUtilization {
                DetailRow(label: "Tiler", value: "\(Int(tiler.rounded())) %", dot: PeekTheme.teal)
            }
            if let inUse = gpu.memoryInUseBytes { DetailRow(label: "Memory in use", value: ByteCountText.memory(inUse)) }
            if let allocated = gpu.memoryAllocatedBytes { DetailRow(label: "Memory set aside", value: ByteCountText.memory(allocated)) }
            if let limit = facts?.recommendedMaxWorkingSetBytes { DetailRow(label: "Memory the GPU can use", value: ByteCountText.memory(limit)) }
            if let used = gpu.vramUsedBytes {
                DetailRow(label: "VRAM", value: ByteCountText.memory(used) + (gpu.vramTotalBytes.map { " / " + ByteCountText.memory($0) } ?? ""))
            }
            DetailRow(label: "GPU", value: gpu.name)
            if let cores = gpu.coreCount { DetailRow(label: "GPU cores", value: String(cores)) }
            if let facts {
                let family = [facts.gpuFamily, facts.supportsMetal3 ? "Metal 3" : nil].compactMap { $0 }.joined(separator: " · ")
                if !family.isEmpty { DetailRow(label: "GPU family", value: family) }
                if let largest = facts.maxBufferBytes { DetailRow(label: "Largest buffer", value: ByteCountText.memory(largest)) }
                DetailRow(label: "Memory", value: facts.hasUnifiedMemory ? "Shared with the Mac (unified)" : "Dedicated VRAM")
                if facts.isRemovable { DetailRow(label: "Connection", value: "External GPU") }
                if facts.isLowPower { DetailRow(label: "Type", value: "Integrated (low power)") }
            }
        }
    }
}

private struct GPUPowerSection: View {
    let snapshot: GPUSnapshot

    var body: some View {
        if let power = snapshot.power {
            let parts: [(String, Double?, Color)] = [("Neural Engine", power.neuralEngineWatts, PeekTheme.accent),
                                                     ("GPU", power.gpuWatts, PeekTheme.teal),
                                                     ("CPU", power.cpuWatts, PeekTheme.amber)]
            let total = parts.compactMap(\.1).reduce(0, +)
            VStack(alignment: .leading, spacing: 6) {
                SectionLabel(text: "Power", trailing: total > 0 ? Watts.label(total) + " total" : nil)
                ForEach(parts, id: \.0) { part in
                    PowerBar(name: part.0, watts: part.1, color: part.2, total: total)
                }
                Text("From macOS's energy counters over the last interval. macOS reports no Neural Engine utilization without administrator rights, so its power is the sign of how hard it is working.")
                    .font(.system(size: 10.5)).foregroundStyle(PeekTheme.muted)
            }
        } else if let note = snapshot.powerNote {
            VStack(alignment: .leading, spacing: 6) {
                SectionLabel(text: "Power")
                Text(note).font(.caption).foregroundStyle(PeekTheme.muted)
            }
        }
    }
}

private struct GPUProcessesSection: View {
    let processes: [GPUProcessUsage]

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            SectionLabel(text: "Using the GPU", trailing: "% of GPU time")
            if processes.isEmpty {
                Text("No process has the GPU open.").font(.caption).foregroundStyle(PeekTheme.muted)
            } else {
                ForEach(processes.prefix(15)) { row in
                    HStack(spacing: 8) {
                        Text(row.name).lineLimit(1)
                        Spacer(minLength: 4)
                        if let percent = row.gpuPercent {
                            Capsule().fill(PeekTheme.accent)
                                .frame(width: max(2, 40 * CGFloat(min(percent, 100) / 100)), height: 4)
                        }
                        Text(row.gpuPercent.map { String(format: "%.1f %%", $0) } ?? "–")
                            .font(.system(size: 12.5, design: .monospaced))
                            .frame(width: 58, alignment: .trailing)
                    }
                    .font(.system(size: 13))
                    .padding(.vertical, 3)
                    .overlay(alignment: .bottom) { Rectangle().fill(PeekTheme.hairline).frame(height: 1) }
                    .help("PID \(row.pid)")
                    .accessibilityElement(children: .combine)
                }
                Text("GPU time each process used since the last sample, where the driver counts it. \"–\" until two samples exist.")
                    .font(.system(size: 10.5)).foregroundStyle(PeekTheme.muted).padding(.top, 2)
            }
        }
    }
}

private struct PowerBar: View {
    let name: String
    let watts: Double?
    let color: Color
    let total: Double

    private var share: CGFloat { total > 0 ? CGFloat((watts ?? 0) / total) : 0 }

    var body: some View {
        HStack(spacing: 8) {
            Text(name).font(.system(size: 13)).foregroundStyle(PeekTheme.muted).frame(width: 100, alignment: .leading)
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(PeekTheme.track)
                    Capsule().fill(color).frame(width: proxy.size.width * share)
                }
            }
            .frame(height: 6)
            Text(watts.map(Watts.label) ?? "–").font(.system(size: 12.5, design: .monospaced)).frame(width: 64, alignment: .trailing)
        }
        .accessibilityElement(children: .combine)
    }
}

private enum Watts {
    static func label(_ value: Double) -> String {
        value < 0.1 ? String(format: "%.0f mW", value * 1000) : String(format: "%.2f W", value)
    }
}
#endif
