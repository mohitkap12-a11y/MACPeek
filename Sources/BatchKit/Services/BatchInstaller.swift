import Foundation
import MacPeekCore

/// Checks and installs batch items. `SystemBatchInstaller` is the real one; tests pass fakes.
public protocol BatchInstalling: Sendable {
    /// Whether each item can be installed here, in order. An item may count on earlier ones (Ollama started by a
    /// Homebrew item before its models).
    func check(_ items: [BatchItem]) async -> [BatchItemCheck]
    /// Installs one item that `check` found ready.
    func install(_ item: BatchItem, progress: @escaping @Sendable (Double?, String?) async -> Void) async -> BatchInstallResult
}

public enum BatchInstallResult: Equatable, Sendable {
    case done
    case failed(String)
}

/// What the installer needs to know about this Mac and where its tools are.
public struct BatchEnvironment: Sendable {
    public var brew: ExecutableLocator
    public var docker: ExecutableLocator
    public var podman: ExecutableLocator
    public var memoryBytes: @Sendable () -> UInt64
    /// Free space on the volume of the home folder, or nil when it can't be read.
    public var freeDiskBytes: @Sendable () -> UInt64?

    public init(brew: ExecutableLocator, docker: ExecutableLocator, podman: ExecutableLocator,
                memoryBytes: @escaping @Sendable () -> UInt64, freeDiskBytes: @escaping @Sendable () -> UInt64?) {
        self.brew = brew
        self.docker = docker
        self.podman = podman
        self.memoryBytes = memoryBytes
        self.freeDiskBytes = freeDiskBytes
    }

    public static let standard = BatchEnvironment(
        brew: ExecutableLocator(candidates: ["/opt/homebrew/bin/brew", "/usr/local/bin/brew"]),
        docker: .standard("docker", extra: ["/Applications/Docker.app/Contents/Resources/bin/docker", "~/.orbstack/bin/docker", "~/.rd/bin/docker"]),
        podman: .standard("podman", extra: ["/opt/podman/bin/podman"]),
        memoryBytes: { ProcessInfo.processInfo.physicalMemory },
        freeDiskBytes: { SystemBatchInstaller.freeDiskBytes() })
}

/// Installs with each tool's own command, run directly with a fixed argument list (never a shell, never `sudo`, input
/// closed so nothing can wait for a password). Homebrew and the container engine run as the person's own user.
public struct SystemBatchInstaller: BatchInstalling {
    /// Kept free after everything a batch downloads, so a batch never fills the disk.
    public static let diskMargin: UInt64 = 5_000_000_000

    private let environment: BatchEnvironment
    private let quick: CommandRunning
    private let long: CommandRunning
    private let ollama: OllamaControlling
    private let sleep: @Sendable (UInt64) async -> Void

    public init(environment: BatchEnvironment = .standard, quick: CommandRunning = ShellCommand(timeout: 60),
                long: CommandRunning = ShellCommand(timeout: 4 * 3600), ollama: OllamaControlling = SystemOllamaClient(),
                sleep: @escaping @Sendable (UInt64) async -> Void = { try? await Task.sleep(nanoseconds: $0) }) {
        self.environment = environment
        self.quick = quick
        self.long = long
        self.ollama = ollama
        self.sleep = sleep
    }

    // MARK: Commands

    static func brewArguments(brew: String, _ arguments: [String]) -> [String] {
        ["HOMEBREW_NO_AUTO_UPDATE=1", "HOMEBREW_NO_ANALYTICS=1", "HOMEBREW_NO_ENV_HINTS=1", "HOMEBREW_NO_INSTALL_CLEANUP=1",
         brew] + arguments
    }

    static func brewList(_ item: BatchItem) -> [String] {
        item.kind == .brewCask ? ["list", "--cask", "--versions", item.name] : ["list", "--formula", "--versions", item.name]
    }

    static func brewInstall(_ item: BatchItem) -> [String] {
        item.kind == .brewCask ? ["install", "--cask", item.name] : ["install", "--formula", item.name]
    }

    static func brewService(_ item: BatchItem) -> [String] { ["services", "start", item.name] }

    // MARK: Check

    public func check(_ items: [BatchItem]) async -> [BatchItemCheck] {
        var results: [BatchItemCheck] = []
        var freeDisk = environment.freeDiskBytes()
        let memory = environment.memoryBytes()
        var ollamaRunning: Bool?
        var ollamaModels: Set<String>?
        for item in items {
            if let problem = BatchValidation.problem(with: item) {
                results.append(BatchItemCheck(item: item, verdict: .blocked, reason: problem))
                continue
            }
            if item.requirements.memoryBytes > 0, item.requirements.memoryBytes > memory {
                results.append(BatchItemCheck(item: item, verdict: .blocked,
                                              reason: "Needs \(Self.gb(item.requirements.memoryBytes)) of memory; this Mac has \(Self.gb(memory))."))
                continue
            }
            let verdict: BatchItemCheck
            switch item.kind {
            case .brewFormula, .brewCask:
                guard let brew = environment.brew.locate() else {
                    verdict = BatchItemCheck(item: item, verdict: .blocked, reason: "Homebrew isn't installed on this Mac.")
                    break
                }
                let output = try? await quick.run("/usr/bin/env", Self.brewArguments(brew: brew, Self.brewList(item)))
                let installed = output.map { $0.status == 0 && !$0.stdout.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty } ?? false
                verdict = BatchItemCheck(item: item, verdict: installed && !item.startService ? .installed : .ready)
            case .ollamaModel:
                if ollamaRunning == nil { ollamaRunning = await ollama.isRunning() }
                let startedEarlier = results.contains {
                    $0.item.kind == .brewFormula && $0.item.name == "ollama" && $0.item.startService && $0.verdict != .blocked
                }
                guard ollamaRunning == true || startedEarlier else {
                    verdict = BatchItemCheck(item: item, verdict: .blocked,
                                             reason: "Ollama isn't running. Add Homebrew “ollama” with Start as a service before it.")
                    break
                }
                if ollamaModels == nil, ollamaRunning == true { ollamaModels = try? await ollama.installedModels() }
                let installed = ollamaModels?.contains(OllamaNames.normalized(item.name)) ?? false
                verdict = BatchItemCheck(item: item, verdict: installed ? .installed : .ready)
            case .containerImage:
                guard let engine = environment.docker.locate() ?? environment.podman.locate() else {
                    verdict = BatchItemCheck(item: item, verdict: .blocked, reason: "No container engine (Docker, OrbStack or Podman) is installed.")
                    break
                }
                let output = try? await quick.run(engine, ["image", "inspect", "--format", "{{.Id}}", item.name])
                verdict = BatchItemCheck(item: item, verdict: output?.status == 0 ? .installed : .ready)
            }
            if verdict.verdict == .ready, item.requirements.diskBytes > 0, let free = freeDisk {
                guard free >= item.requirements.diskBytes + Self.diskMargin else {
                    results.append(BatchItemCheck(item: item, verdict: .blocked,
                                                  reason: "Needs \(Self.gb(item.requirements.diskBytes)) of disk space; \(Self.gb(free)) is free."))
                    continue
                }
                freeDisk = free - item.requirements.diskBytes
            }
            results.append(verdict)
        }
        return results
    }

    // MARK: Install

    public func install(_ item: BatchItem, progress: @escaping @Sendable (Double?, String?) async -> Void) async -> BatchInstallResult {
        if let problem = BatchValidation.problem(with: item) { return .failed(problem) }
        switch item.kind {
        case .brewFormula, .brewCask: return await installBrew(item, progress: progress)
        case .ollamaModel: return await pullModel(item, progress: progress)
        case .containerImage: return await pullImage(item, progress: progress)
        }
    }

    private func installBrew(_ item: BatchItem, progress: @escaping @Sendable (Double?, String?) async -> Void) async -> BatchInstallResult {
        guard let brew = environment.brew.locate() else { return .failed("Homebrew isn't installed on this Mac.") }
        await progress(nil, "Installing with Homebrew")
        let output: CommandOutput
        do {
            output = try await long.run("/usr/bin/env", Self.brewArguments(brew: brew, Self.brewInstall(item)))
        } catch {
            return .failed(error is CancellationError || (error as? CommandError) == .cancelled ? "Cancelled." : "Homebrew did not finish.")
        }
        guard output.status == 0 else { return .failed(Self.brewFailure(item, output: output)) }
        if item.startService {
            await progress(nil, "Starting \(item.name)")
            let service = try? await quick.run("/usr/bin/env", Self.brewArguments(brew: brew, Self.brewService(item)))
            guard service?.status == 0 else { return .failed("Installed, but Homebrew could not start \(item.name) as a service.") }
        }
        return .done
    }

    /// A fixed message picked by what Homebrew said; its own text is never shown.
    static func brewFailure(_ item: BatchItem, output: CommandOutput) -> String {
        let text = (output.stdout + "\n" + output.stderr).lowercased()
        if text.contains("sudo") || text.contains("password") || text.contains("administrator") {
            return "\(item.name) needs an administrator password to install. Batches never use one."
        }
        if text.contains("no available formula") || text.contains("no cask with this name") || text.contains("no formulae or casks found") {
            return "Homebrew has no package named \(item.name)."
        }
        if text.contains("could not resolve host") || text.contains("failed to download") || text.contains("curl:") {
            return "The download failed. Check this Mac's internet connection."
        }
        return "Homebrew could not install \(item.name)."
    }

    private func pullModel(_ item: BatchItem, progress: @escaping @Sendable (Double?, String?) async -> Void) async -> BatchInstallResult {
        // Ollama started by an earlier item can take a few seconds to answer.
        var running = await ollama.isRunning()
        var waited = 0
        while !running, waited < 15 {
            await sleep(1_000_000_000)
            waited += 1
            running = await ollama.isRunning()
        }
        guard running else { return .failed(OllamaError.notRunning.localizedDescription) }
        do {
            try await ollama.pull(item.name) { fraction, status in await progress(fraction, Self.ollamaStatus(status, fraction)) }
            return .done
        } catch is CancellationError {
            return .failed("Cancelled.")
        } catch let error as OllamaError {
            return .failed(error.localizedDescription)
        } catch {
            return .failed("The download from Ollama stopped. Check this Mac's internet connection.")
        }
    }

    static func ollamaStatus(_ status: String, _ fraction: Double?) -> String {
        if status.hasPrefix("pulling"), let fraction { return "Downloading \(Int((fraction * 100).rounded(.down)))%" }
        if status.hasPrefix("pulling") { return "Downloading" }
        if status.contains("verifying") { return "Checking the download" }
        if status == "success" { return "Done" }
        return "Preparing"
    }

    private func pullImage(_ item: BatchItem, progress: @escaping @Sendable (Double?, String?) async -> Void) async -> BatchInstallResult {
        guard let engine = environment.docker.locate() ?? environment.podman.locate() else {
            return .failed("No container engine (Docker, OrbStack or Podman) is installed.")
        }
        await progress(nil, "Pulling the image")
        let output: CommandOutput
        do {
            output = try await long.run(engine, ["pull", item.name])
        } catch {
            return .failed("The image download did not finish.")
        }
        guard output.status == 0 else {
            let text = output.stderr.lowercased()
            if text.contains("cannot connect") || text.contains("is the docker daemon running") {
                return .failed("The container engine isn't running on this Mac.")
            }
            if text.contains("not found") || text.contains("manifest unknown") || text.contains("denied") {
                return .failed("The registry has no image \(item.name), or it needs a sign-in.")
            }
            return .failed("Could not pull \(item.name).")
        }
        return .done
    }

    // MARK: Helpers

    static func gb(_ bytes: UInt64) -> String {
        let value = Double(bytes) / 1_000_000_000
        return value >= 10 ? "\(Int(value.rounded())) GB" : String(format: "%.1f GB", value)
    }

    public static func freeDiskBytes() -> UInt64? {
        let home = FileManager.default.homeDirectoryForCurrentUser
        #if os(macOS)
        if let values = try? home.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]),
           let capacity = values.volumeAvailableCapacityForImportantUsage {
            return UInt64(max(capacity, 0))
        }
        #endif
        guard let attributes = try? FileManager.default.attributesOfFileSystem(forPath: home.path),
              let free = attributes[.systemFreeSize] as? NSNumber else { return nil }
        return free.uint64Value
    }
}
