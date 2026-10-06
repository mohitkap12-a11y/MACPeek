import Foundation

public struct CommandOutput: Sendable {
    public let stdout: String
    public let stderr: String
    public let status: Int32

    public init(stdout: String, stderr: String, status: Int32) {
        self.stdout = stdout
        self.stderr = stderr
        self.status = status
    }
}

public enum CommandError: Error, LocalizedError, Equatable {
    case timedOut(String)
    case cancelled

    public var errorDescription: String? {
        switch self {
        case .timedOut(let command): return "\(command) did not finish in time."
        case .cancelled: return "The command was cancelled."
        }
    }
}

/// Abstraction over command execution so discovery can be tested without a shell.
public protocol CommandRunning: Sendable {
    func run(_ executable: String, _ arguments: [String]) async throws -> CommandOutput
}

private final class DataBox: @unchecked Sendable {
    var data = Data()
}

/// Tracks the child so a timeout or task cancellation can terminate it.
private final class ProcessBox: @unchecked Sendable {
    private let lock = NSLock()
    private var process: Process?
    private(set) var cancelled = false
    private(set) var timedOut = false

    func attach(_ process: Process) {
        lock.lock(); defer { lock.unlock() }
        self.process = process
        if cancelled, process.isRunning { process.terminate() }
    }

    func cancel() {
        lock.lock(); defer { lock.unlock() }
        cancelled = true
        if let process, process.isRunning { process.terminate() }
    }

    func timeout() {
        lock.lock(); defer { lock.unlock() }
        guard let process, process.isRunning else { return }
        timedOut = true
        process.terminate()
    }
}

/// Runs an executable directly (never through a shell, so no injection surface).
/// A hung child is terminated after `timeout`, closing its pipes so the awaiting scan always ends.
public struct ShellCommand: CommandRunning {
    private let timeout: TimeInterval

    public init(timeout: TimeInterval = 10) {
        self.timeout = timeout
    }

    public func run(_ executable: String, _ arguments: [String]) async throws -> CommandOutput {
        let box = ProcessBox()
        let timeout = self.timeout
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                DispatchQueue.global(qos: .userInitiated).async {
                    let process = Process()
                    process.executableURL = URL(fileURLWithPath: executable)
                    process.arguments = arguments
                    let out = Pipe()
                    let err = Pipe()
                    process.standardOutput = out
                    process.standardError = err
                    process.standardInput = FileHandle.nullDevice
                    do {
                        try process.run()
                    } catch {
                        continuation.resume(throwing: error)
                        return
                    }
                    box.attach(process)
                    DispatchQueue.global().asyncAfter(deadline: .now() + timeout) { box.timeout() }

                    // Drain stderr concurrently so a full pipe can never block the child.
                    let errBox = DataBox()
                    let group = DispatchGroup()
                    group.enter()
                    DispatchQueue.global(qos: .userInitiated).async {
                        errBox.data = err.fileHandleForReading.readDataToEndOfFile()
                        group.leave()
                    }
                    let outData = out.fileHandleForReading.readDataToEndOfFile()
                    group.wait()
                    process.waitUntilExit()

                    if box.timedOut {
                        continuation.resume(throwing: CommandError.timedOut(URL(fileURLWithPath: executable).lastPathComponent))
                    } else if box.cancelled {
                        continuation.resume(throwing: CommandError.cancelled)
                    } else {
                        continuation.resume(returning: CommandOutput(
                            stdout: String(decoding: outData, as: UTF8.self),
                            stderr: String(decoding: errBox.data, as: UTF8.self),
                            status: process.terminationStatus
                        ))
                    }
                }
            }
        } onCancel: {
            box.cancel()
        }
    }
}
