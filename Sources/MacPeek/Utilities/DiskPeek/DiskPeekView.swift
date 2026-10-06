#if os(macOS)
import SwiftUI
import DiskPeekKit

/// DiskPeek's screen: which processes are reading and writing the disk, sampled while this screen is open.
struct DiskPeekView: View {
    @EnvironmentObject private var store: DiskStore

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Picker("Order by", selection: $store.sort) {
                    ForEach(DiskSort.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .accessibilityLabel("Order by")
                StatusBadge(text: "Sampled", tone: .info)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            Divider()
            content
            Divider()
            footer
        }
    }

    @ViewBuilder private var content: some View {
        if let error = store.error, store.activity.isEmpty {
            ErrorState(message: error, retryTitle: "Try again") { store.startSampling() }
        } else if store.isWaitingForSecondSample {
            VStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Taking a first sample…").font(.caption).foregroundStyle(.secondary)
                Text("Rates appear after the second sample, a couple of seconds from now.")
                    .font(.caption2).foregroundStyle(.tertiary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if store.rows.isEmpty {
            EmptyState(symbol: "internaldrive", title: "No disk activity since you opened this screen",
                       message: "Processes appear here as soon as they read or write.")
        } else {
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(store.rows) { row in
                        DiskRow(row: row)
                        Divider().opacity(0.4)
                    }
                }
            }
            .frame(maxHeight: .infinity)
        }
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Values are sampled every \(Int(store.interval)) s while this screen is open. Sampling stops when you leave it.")
            if store.unreadableProcesses > 0 {
                Text("\(store.unreadableProcesses) processes (other users' or protected) cannot be read and are not shown.")
            }
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }
}

private struct DiskRow: View {
    let row: DiskActivity

    var body: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 1) {
                Text(row.name).font(.system(size: 13, weight: .medium)).lineLimit(1)
                Text("PID \(row.pid) · \(ByteSize.label(Double(row.readSinceOpened))) read, \(ByteSize.label(Double(row.writtenSinceOpened))) written since opened")
                    .font(.caption2).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 4)
            VStack(alignment: .trailing, spacing: 1) {
                Text("R \(ByteRate.label(row.readBytesPerSecond))").font(.caption.monospacedDigit())
                Text("W \(ByteRate.label(row.writeBytesPerSecond))").font(.caption.monospacedDigit())
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .accessibilityElement(children: .combine)
    }
}
#endif
