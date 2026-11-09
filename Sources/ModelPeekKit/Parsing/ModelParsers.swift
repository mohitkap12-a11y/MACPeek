import Foundation
import MacPeekCore

/// One process as two `ps` runs describe it: `ps -axo pid=,ppid=,comm=` and `ps -axww -o pid=,args=`.
public struct ProcessLine: Equatable, Sendable {
    public let pid: Int
    public let ppid: Int
    /// The executable as `ps` prints `comm` (often a full path; it can contain spaces).
    public let command: String
    /// The command line. Only the runner's model argument is taken from it; the line itself is never kept or shown,
    /// because command lines can contain tokens.
    public let arguments: String

    public init(pid: Int, ppid: Int, command: String, arguments: String) {
        self.pid = pid
        self.ppid = ppid
        self.command = command
        self.arguments = arguments
    }

    public var name: String {
        command.split(separator: "/").last.map(String.init) ?? command
    }
}

public enum ProcessLineParser {
    private static let comm = NSRegularExpression.compile(#"^\s*(\d+)\s+(\d+)\s+(.+?)\s*$"#)
    private static let args = NSRegularExpression.compile(#"^\s*(\d+)\s+(.*?)\s*$"#)

    public static func parse(comm commText: String, args argsText: String) -> [ProcessLine] {
        var arguments: [Int: String] = [:]
        for line in argsText.split(whereSeparator: \.isNewline) {
            if let g = args.groups(in: String(line)), let pid = g[1].flatMap(Int.init) { arguments[pid] = g[2] ?? "" }
        }
        return commText.split(whereSeparator: \.isNewline).compactMap { line in
            guard let g = comm.groups(in: String(line)), let pid = g[1].flatMap(Int.init), let ppid = g[2].flatMap(Int.init),
                  let command = g[3] else { return nil }
            return ProcessLine(pid: pid, ppid: ppid, command: command, arguments: arguments[pid] ?? "")
        }
    }
}

/// Recognises runner processes by executable and, for Python-based MLX, by the module on the command line.
public enum RunnerMatcher {
    public struct Match: Equatable, Sendable {
        public let kind: RunnerKind
        public let role: String
    }

    private static let llamaCppTools: Set<String> = ["llama-server", "llama-cli", "llama-run", "llama-simple", "llama-mtmd-cli",
                                                     "llama-embedding", "llama-bench", "llama-gguf", "rpc-server"]

    public static func match(_ process: ProcessLine) -> Match? {
        let name = process.name
        let lowerName = name.lowercased()
        let command = process.command
        let tokens = process.arguments.split(separator: " ").map(String.init)

        if lowerName == "ollama" || lowerName == "ollama_llama_server" || lowerName == "ollama-runner" {
            if lowerName != "ollama" || tokens.contains("runner") { return Match(kind: .ollama, role: "model runner") }
            return Match(kind: .ollama, role: tokens.contains("serve") ? "server" : "ollama")
        }
        if command.contains("/Ollama.app/") { return Match(kind: .ollama, role: "app") }

        if command.contains("/LM Studio.app/") { return Match(kind: .lmStudio, role: name == "LM Studio" ? "app" : "app helper") }
        if command.contains("/.lmstudio/") || command.contains("/.cache/lm-studio/") {
            return Match(kind: .lmStudio, role: lowerName == "lms" ? "command-line tool" : "engine")
        }

        if lowerName == "llamafile" || lowerName.hasSuffix(".llamafile") || tokens.first?.lowercased().hasSuffix(".llamafile") == true {
            return Match(kind: .llamafile, role: "server")
        }
        if llamaCppTools.contains(lowerName) {
            return Match(kind: .llamaCpp, role: lowerName == "llama-server" ? "server" : name)
        }

        let mlxModule = tokens.first { token in
            let t = token.lowercased()
            return t.hasPrefix("mlx_lm") || t.hasPrefix("mlx-lm") || t.hasPrefix("mlx_vlm") || t.hasPrefix("mlx-vlm")
                || t.hasSuffix("/mlx_lm.server") || t.hasSuffix("/mlx_lm.generate") || t.hasSuffix("/mlx_lm.chat")
        }
        if let mlxModule {
            let isServer = mlxModule.contains("server") || tokens.contains("server")
            return Match(kind: .mlx, role: isServer ? "server" : "script")
        }
        return nil
    }

    /// The model a runner was started with, from `-m`/`--model`/`--hf-repo` (or `--model=`). Ollama's runners point at
    /// content-addressed blobs, which say nothing to a person, so they are skipped (Ollama's API names the model).
    public static func modelArgument(_ process: ProcessLine) -> String? {
        let tokens = process.arguments.split(separator: " ").map(String.init)
        var value: String?
        for (index, token) in tokens.enumerated() {
            if ["-m", "--model", "-hf", "-hfr", "--hf-repo"].contains(token), index + 1 < tokens.count {
                // `python -m mlx_lm.server` names a Python module, not a model.
                if token == "-m", tokens[index + 1].lowercased().hasPrefix("mlx") { continue }
                value = tokens[index + 1]
                break
            }
            if token.hasPrefix("--model=") { value = String(token.dropFirst("--model=".count)); break }
            if token.hasPrefix("--hf-repo=") { value = String(token.dropFirst("--hf-repo=".count)); break }
        }
        guard var model = value, !model.isEmpty, !model.hasPrefix("-") else { return nil }
        if model.contains("/blobs/sha256") || model.hasPrefix("sha256") { return nil }
        if model.hasPrefix("/") || model.hasPrefix("~") || model.hasPrefix(".") {
            model = model.split(separator: "/").last.map(String.init) ?? model
        }
        return model
    }
}

/// Ollama's `GET /api/ps`: the models loaded in memory right now.
public enum OllamaPSParser {
    public static func parse(_ data: Data) -> [LoadedModel]? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        guard let models = root["models"] as? [Any] else { return root["models"] == nil ? nil : [] }
        return models.compactMap { $0 as? [String: Any] }.compactMap { object in
            guard let name = LooseJSON.text(object, "name") ?? LooseJSON.text(object, "model") else { return nil }
            let details = LooseJSON.object(object, "details") ?? [:]
            return LoadedModel(name: name, sizeBytes: LooseJSON.uint64(object, "size"), gpuBytes: LooseJSON.uint64(object, "size_vram"),
                               contextLength: LooseJSON.int(object, "context_length"),
                               quantization: LooseJSON.text(details, "quantization_level"),
                               parameterSize: LooseJSON.text(details, "parameter_size"), family: LooseJSON.text(details, "family"),
                               expiresAt: LooseJSON.text(object, "expires_at"), source: .api)
        }
    }
}

/// LM Studio's `GET /api/v0/models`: every downloaded model, with `state` "loaded" for the ones in memory.
public enum LMStudioModelsParser {
    public static func parse(_ data: Data) -> [LoadedModel]? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any], let list = root["data"] as? [Any] else { return nil }
        return list.compactMap { $0 as? [String: Any] }.compactMap { object in
            guard LooseJSON.text(object, "state")?.lowercased() == "loaded", let name = LooseJSON.text(object, "id") else { return nil }
            return LoadedModel(name: name, contextLength: LooseJSON.int(object, "loaded_context_length") ?? LooseJSON.int(object, "max_context_length"),
                               quantization: LooseJSON.text(object, "quantization"), family: LooseJSON.text(object, "arch"),
                               source: .api)
        }
    }
}
