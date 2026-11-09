#if os(macOS)
import SwiftUI
import MacPeekCore
import ModelPeekKit

/// ModelPeek's screen: one card per local LLM runner, with its loaded models and what its processes use.
struct ModelPeekView: View {
    @EnvironmentObject private var store: ModelStore

    var body: some View {
        VStack(spacing: 0) {
            if let error = store.error, store.snapshot != nil {
                BannerView(banner: Banner(kind: .error, text: "Couldn't refresh: \(error) Showing the last reading."))
            }
            content
            Divider()
            HStack {
                Text("Local only · asks runners' APIs on 127.0.0.1")
                Spacer()
                Button { Task { await store.refreshOnce() } } label: { Image(systemName: "arrow.clockwise") }
                    .buttonStyle(.borderless)
                    .help("Refresh now")
                    .keyboardShortcut("r", modifiers: .command)
                    .accessibilityLabel("Refresh local models")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
        }
    }

    @ViewBuilder private var content: some View {
        if let error = store.error, store.snapshot == nil {
            ErrorState(message: error, retryTitle: "Try again") { Task { await store.refreshOnce() } }
        } else if let snapshot = store.snapshot {
            if snapshot.runners.isEmpty {
                EmptyState(symbol: "brain", title: "No local LLM runner is running",
                           message: "ModelPeek recognises Ollama, LM Studio, MLX (mlx_lm), llama.cpp and llamafile.")
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(snapshot.runners) { runner in RunnerCard(runner: runner) }
                    }
                    .padding(12)
                }
                .frame(maxHeight: .infinity)
            }
        } else {
            VStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Looking for local LLM runners…").font(.caption).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

private struct RunnerCard: View {
    let runner: LLMRunner
    @State private var showProcesses = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                IconTile(symbol: "brain")
                VStack(alignment: .leading, spacing: 1) {
                    Text(runner.kind.displayName).font(.system(size: 13, weight: .semibold))
                    Text(usage).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                StatusBadge(text: runner.models.isEmpty ? "No model loaded" : (runner.models.count == 1 ? "1 model" : "\(runner.models.count) models"),
                            tone: runner.models.isEmpty ? .neutral : .info)
            }
            ForEach(runner.models) { model in ModelRow(model: model) }
            if let note = runner.note { Text(note).font(.caption2).foregroundStyle(.secondary) }
            DisclosureGroup("Processes (\(runner.processes.count))", isExpanded: $showProcesses) {
                VStack(alignment: .leading, spacing: 3) {
                    ForEach(runner.processes) { process in
                        HStack {
                            Text("\(process.name) · \(process.role)").font(.caption).lineLimit(1)
                            Text("PID \(process.pid)").font(.caption2).foregroundStyle(.secondary)
                            Spacer()
                            Text(process.memoryFootprintBytes.map(ByteCountText.memory) ?? "—").font(.caption.monospacedDigit())
                        }
                    }
                }
                .padding(.top, 4)
            }
            .font(.caption)
        }
        .peekCard()
    }

    private var usage: String {
        var parts: [String] = []
        if let memory = runner.memoryFootprintBytes { parts.append(ByteCountText.memory(memory) + " memory") }
        if let cpu = runner.cpuPercent { parts.append(String(format: "%.0f%% CPU", cpu)) }
        if let gpu = runner.gpuPercent { parts.append(String(format: "%.0f%% GPU", gpu)) }
        return parts.isEmpty ? "Measuring…" : parts.joined(separator: " · ")
    }
}

private struct ModelRow: View {
    let model: LoadedModel

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(model.name).font(.system(size: 12, weight: .medium, design: .monospaced)).lineLimit(1).textSelection(.enabled)
                Spacer()
                if let split = model.processorSplit { StatusBadge(text: split, tone: .info) }
            }
            let details = detailText
            if !details.isEmpty { Text(details).font(.caption2).foregroundStyle(.secondary) }
        }
        .padding(8)
        .background(Color.primary.opacity(0.03), in: RoundedRectangle(cornerRadius: 8))
    }

    private var detailText: String {
        var parts: [String] = []
        if let size = model.sizeBytes { parts.append(ByteCountText.memory(size)) }
        if let gpu = model.gpuBytes, model.sizeBytes != nil { parts.append(ByteCountText.memory(gpu) + " on GPU") }
        if let parameters = model.parameterSize { parts.append(parameters) }
        if let quantization = model.quantization { parts.append(quantization) }
        if let context = model.contextLength { parts.append("\(context) context") }
        if model.source == .commandLine { parts.append("from its command line") }
        return parts.joined(separator: " · ")
    }
}
#endif
