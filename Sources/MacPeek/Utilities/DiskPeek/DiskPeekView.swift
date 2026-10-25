#if os(macOS)
import SwiftUI
import MacPeekCore
import DiskPeekKit

/// DiskPeek's screen: how full each drive is, and which processes are reading and writing the disk, sampled while
/// this screen is open.
struct DiskPeekView: View {
    @EnvironmentObject private var store: DiskStore

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    StorageSection()
                    ProcessesSection()
                }
                .padding(14)
            }
            .frame(maxHeight: .infinity)
        }
        .background(PeekTheme.ground)
    }
}

/// The startup disk as a large card (activity and capacity), other drives as compact rows.
private struct StorageSection: View {
    @EnvironmentObject private var store: DiskStore

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let error = store.volumesError {
                Text("Drive capacity is not available: \(error)").font(.caption).foregroundStyle(PeekTheme.warningText)
            } else if !store.hasReadVolumes {
                Text("Reading drives…").font(.caption).foregroundStyle(PeekTheme.muted)
            } else if store.volumes.isEmpty {
                Text("No local drives to show.").font(.caption).foregroundStyle(PeekTheme.muted)
            } else {
                if let main = store.volumes.first { MainVolumeCard(volume: main) }
                ForEach(store.volumes.dropFirst().prefix(3)) { volume in VolumeRow(volume: volume) }
                if store.volumes.count > 4 {
                    Text("\(store.volumes.count - 4) more drives are not shown.").font(.caption2).foregroundStyle(PeekTheme.muted)
                }
            }
        }
    }
}

private struct MainVolumeCard: View {
    @EnvironmentObject private var store: DiskStore
    let volume: VolumeCapacity

    private var chartMaximum: Double {
        max((store.readHistory.values + store.writeHistory.values).max() ?? 0, 1) * 1.1
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text(volume.name).font(.system(size: 14, weight: .semibold)).lineLimit(1)
                if let kind = volume.kindLabel { Text(kind).font(.system(size: 11)).foregroundStyle(PeekTheme.muted) }
                Spacer(minLength: 4)
                if volume.isLowOnSpace { StatusBadge(text: "Low space", tone: .warning) }
                SampledPill()
            }
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    rate("W", store.totalWriteRate, PeekTheme.red)
                    rate("R", store.totalReadRate, PeekTheme.accent)
                }
                .frame(minWidth: 96, alignment: .leading)
                HistoryChart(series: [.init(values: store.readHistory.values, color: PeekTheme.accent),
                                      .init(values: store.writeHistory.values, color: PeekTheme.red, filled: false)],
                             maximum: chartMaximum)
                    .frame(height: 44)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Your processes are reading \(ByteRate.label(store.totalReadRate)) and writing \(ByteRate.label(store.totalWriteRate))")
            SegmentedBar(parts: [
                .init(fraction: Double(volume.usedBytes) / Double(max(volume.totalBytes, 1)),
                      color: volume.isLowOnSpace ? PeekTheme.amber : PeekTheme.accent),
                .init(fraction: Double(volume.purgeableBytes) / Double(max(volume.totalBytes, 1)), color: PeekTheme.teal),
            ], height: 8)
            HStack {
                Text("\(ByteCountText.storage(volume.availableBytes)) available of \(ByteCountText.storage(volume.totalBytes))")
                Spacer(minLength: 4)
                Text("\(Int(((1 - volume.usedFraction) * 100).rounded()))% free").font(.system(size: 12, design: .monospaced))
            }
            .font(.system(size: 12))
            .foregroundStyle(PeekTheme.muted)
            if volume.purgeableBytes > 0 {
                HStack(spacing: 6) {
                    LegendDot(color: PeekTheme.teal)
                    Text("\(ByteCountText.storage(volume.purgeableBytes)) of it macOS frees by itself when needed")
                }
                .font(.system(size: 11.5))
                .foregroundStyle(PeekTheme.muted)
            }
            Text("Read and write rates of your processes together.")
                .font(.system(size: 10.5)).foregroundStyle(PeekTheme.muted)
        }
        .themedCard(radius: 12, padding: 12)
    }

    private func rate(_ label: String, _ value: Double, _ color: Color) -> some View {
        HStack(spacing: 6) {
            LegendDot(color: color)
            Text("\(label) \(ByteRate.label(value))").font(.system(size: 12.5, design: .monospaced))
        }
    }
}

private struct VolumeRow: View {
    let volume: VolumeCapacity

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text(volume.name).font(.system(size: 13, weight: .medium)).lineLimit(1)
                if let kind = volume.kindLabel { Text(kind).font(.system(size: 11)).foregroundStyle(PeekTheme.muted) }
                Spacer(minLength: 4)
                if volume.isLowOnSpace { StatusBadge(text: "Low space", tone: .warning) }
                Text("\(ByteCountText.storage(volume.availableBytes)) free")
                    .font(.system(size: 12, design: .monospaced)).foregroundStyle(PeekTheme.muted)
            }
            SegmentedBar(parts: [.init(fraction: volume.usedFraction,
                                       color: volume.isLowOnSpace ? PeekTheme.amber : PeekTheme.accent)], height: 5)
        }
        .themedCard(radius: 10, padding: 10)
        .accessibilityElement(children: .combine)
    }
}

private struct ProcessesSection: View {
    @EnvironmentObject private var store: DiskStore

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                SectionLabel(text: "Top processes")
                Picker("Order by", selection: $store.sort) {
                    ForEach(DiskSort.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
                .accessibilityLabel("Order by")
            }
            if let error = store.error, store.activity.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Disk activity could not be read: \(error)").font(.caption).foregroundStyle(PeekTheme.warningText)
                    Button("Try again") { store.startSampling() }.controlSize(.small)
                }
            } else if store.isWaitingForSecondSample {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Taking a first sample… rates appear after the second one.").font(.caption).foregroundStyle(PeekTheme.muted)
                }
            } else if store.rows.isEmpty {
                Text("No disk activity since you opened this screen. Processes appear as soon as they read or write.")
                    .font(.caption).foregroundStyle(PeekTheme.muted)
            } else {
                HStack(spacing: 8) {
                    Text("Process")
                    Spacer(minLength: 4)
                    columnHeader("Read", PeekTheme.accent).frame(width: 76, alignment: .trailing)
                    columnHeader("Write", PeekTheme.red).frame(width: 70, alignment: .trailing)
                }
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundStyle(PeekTheme.muted)
                ForEach(store.rows) { row in
                    HStack(spacing: 8) {
                        Text(row.name).font(.system(size: 13)).lineLimit(1)
                        Spacer(minLength: 4)
                        Text(store.sort == .rate ? ByteRate.label(row.readBytesPerSecond) : ByteSize.label(Double(row.readSinceOpened)))
                            .frame(width: 76, alignment: .trailing)
                        Text(store.sort == .rate ? ByteRate.label(row.writeBytesPerSecond) : ByteSize.label(Double(row.writtenSinceOpened)))
                            .frame(width: 70, alignment: .trailing)
                    }
                    .font(.system(size: 12.5, design: .monospaced))
                    .padding(.vertical, 3)
                    .overlay(alignment: .bottom) { Rectangle().fill(PeekTheme.hairline).frame(height: 1) }
                    .help("PID \(row.pid) · \(ByteSize.label(Double(row.readSinceOpened))) read, \(ByteSize.label(Double(row.writtenSinceOpened))) written since opened")
                    .accessibilityElement(children: .combine)
                }
            }
        }
    }

    private func columnHeader(_ title: String, _ color: Color) -> some View {
        HStack(spacing: 4) {
            LegendDot(color: color, size: 7)
            Text(title)
        }
    }
}
#endif
