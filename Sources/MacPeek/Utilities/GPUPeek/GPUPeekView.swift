#if os(macOS)
import SwiftUI
import MacPeekCore
import GPUPeekKit

/// GPUPeek's screen: GPU load and memory, Neural Engine and power (Apple silicon), and processes using the GPU.
struct GPUPeekView: View {
    @EnvironmentObject private var store: GPUStore

    var body: some View {
        VStack(spacing: 0) {
            if let error = store.error, store.snapshot != nil {
                BannerView(banner: Banner(kind: .error, text: "Couldn't refresh: \(error) Showing the last reading."))
            }
            content
            Divider()
            HStack {
                Text("As the GPU driver and macOS report it · read-only")
                Spacer()
                SampledPill()
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
        }
    }

    @ViewBuilder private var content: some View {
        if let error = store.error, store.snapshot == nil {
            ErrorState(message: error, retryTitle: "Try again") { Task { await store.sample() } }
        } else if let snapshot = store.snapshot {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if snapshot.gpus.isEmpty {
                        EmptyState(symbol: "cpu", title: "macOS lists no GPU", message: "No IOAccelerator service was found.")
                    }
                    ForEach(snapshot.gpus) { gpu in GPUCard(gpu: gpu) }
                    if snapshot.hasNeuralEngine || snapshot.power != nil || snapshot.powerNote != nil { PowerCard(snapshot: snapshot) }
                    ProcessesCard(snapshot: snapshot)
                }
                .padding(12)
            }
            .frame(maxHeight: .infinity)
        } else {
            VStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Reading the GPU…").font(.caption).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

private struct GPUCard: View {
    @EnvironmentObject private var store: GPUStore
    let gpu: GPUInfo

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 14) {
                RingGauge(fraction: gpu.utilizationFraction ?? 0, color: PeekTheme.accent) {
                    VStack(spacing: 0) {
                        Text(gpu.deviceUtilization.map { "\(Int($0.rounded()))%" } ?? "—").font(.system(size: 16, weight: .semibold).monospacedDigit())
                        Text("busy").font(.caption2).foregroundStyle(.secondary)
                    }
                }
                .frame(width: 74, height: 74)
                VStack(alignment: .leading, spacing: 4) {
                    Text(gpu.name).font(.system(size: 13, weight: .semibold))
                    KeyValueRows(rows: rows)
                }
                Spacer(minLength: 0)
            }
            if store.utilizationHistory.values.count > 1 {
                HistoryChart(series: [.init(values: store.utilizationHistory.values, color: PeekTheme.accent)], maximum: 100)
                    .frame(height: 44)
                Text("GPU busy since opened").font(.caption2).foregroundStyle(.tertiary)
            }
        }
        .peekCard()
    }

    private var rows: [(label: String, value: String)] {
        var rows: [(label: String, value: String)] = []
        if let cores = gpu.coreCount { rows.append(("Cores", String(cores))) }
        if let renderer = gpu.rendererUtilization { rows.append(("Renderer", "\(Int(renderer))%")) }
        if let tiler = gpu.tilerUtilization { rows.append(("Tiler", "\(Int(tiler))%")) }
        if let inUse = gpu.memoryInUseBytes {
            rows.append(("GPU memory", ByteCountText.memory(inUse) + " in use" + (gpu.unifiedMemory ? " (shared with the Mac)" : "")))
        }
        if let allocated = gpu.memoryAllocatedBytes { rows.append(("Set aside", ByteCountText.memory(allocated))) }
        if let used = gpu.vramUsedBytes {
            rows.append(("VRAM", ByteCountText.memory(used) + (gpu.vramTotalBytes.map { " of " + ByteCountText.memory($0) } ?? "")))
        }
        return rows
    }
}

private struct PowerCard: View {
    @EnvironmentObject private var store: GPUStore
    let snapshot: GPUSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Neural Engine and power").font(.system(size: 13, weight: .semibold))
            if let power = snapshot.power {
                KeyValueRows(rows: [
                    ("Neural Engine", power.neuralEngineWatts.map { Self.watts($0) + (power.neuralEngineActive == true ? " · working" : " · idle") } ?? "Not reported"),
                    ("GPU", power.gpuWatts.map(Self.watts) ?? "Not reported"),
                    ("CPU", power.cpuWatts.map(Self.watts) ?? "Not reported"),
                ])
                if store.neuralEngineHistory.values.count > 1 {
                    HistoryChart(series: [.init(values: store.neuralEngineHistory.values, color: .purple)],
                                 maximum: max(store.neuralEngineHistory.values.max() ?? 1, 1))
                        .frame(height: 36)
                }
            } else if let note = snapshot.powerNote {
                Text(note).font(.caption).foregroundStyle(.secondary)
            } else {
                Text("Measuring… power appears with the next reading.").font(.caption).foregroundStyle(.secondary)
            }
            Text("macOS does not report Neural Engine utilization to apps without administrator rights, so GPUPeek shows the power it draws instead: 0 W means idle. Values come from macOS's energy counters (IOReport), the same source powermetrics uses.")
                .font(.caption2).foregroundStyle(.tertiary)
        }
        .peekCard()
    }

    private static func watts(_ value: Double) -> String {
        value < 0.1 ? String(format: "%.0f mW", value * 1000) : String(format: "%.2f W", value)
    }
}

private struct ProcessesCard: View {
    let snapshot: GPUSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionLabel(text: "Processes using the GPU", trailing: "\(snapshot.processes.count)")
            if snapshot.processes.isEmpty {
                Text("macOS lists no GPU clients.").font(.caption).foregroundStyle(.secondary)
            }
            ForEach(snapshot.processes.prefix(15)) { process in
                HStack {
                    Text(process.name).font(.caption).lineLimit(1)
                    Text("PID \(process.pid)").font(.caption2).foregroundStyle(.secondary)
                    Spacer()
                    Text(process.gpuPercent.map { String(format: "%.1f%%", $0) } ?? "—").font(.caption.monospacedDigit())
                }
            }
            Text("GPU share is the GPU time each process used since the last reading, where the driver counts it.")
                .font(.caption2).foregroundStyle(.tertiary)
        }
        .peekCard()
    }
}
#endif
