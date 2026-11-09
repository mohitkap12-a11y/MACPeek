import Foundation
import MacPeekCore

/// One job in the user's launchd domain (`launchctl list`).
public struct LaunchdJob: Equatable, Codable, Sendable {
    public let label: String
    public let pid: Int?
    /// The last exit status launchd recorded (0 when it never failed).
    public let lastExitStatus: Int?

    public init(label: String, pid: Int?, lastExitStatus: Int?) {
        self.label = label
        self.pid = pid
        self.lastExitStatus = lastExitStatus
    }

    /// GUI apps opened through Launch Services appear as `application.<bundle id>.<numbers>`.
    public var isApplication: Bool { label.hasPrefix("application.") }

    /// `application.com.apple.Safari.123.456` → `com.apple.Safari`.
    public var bundleIdentifier: String? {
        guard isApplication else { return nil }
        var parts = label.dropFirst("application.".count).split(separator: ".").map(String.init)
        while let last = parts.last, Int(last) != nil { parts.removeLast() }
        return parts.isEmpty ? nil : parts.joined(separator: ".")
    }
}

/// `launchctl print gui/<uid>/<label>`: what launchd will do with the job. Only the fields MacPeek needs.
public struct LaunchdJobDetails: Equatable, Codable, Sendable {
    /// The job's property list, when it came from one.
    public let plistPath: String?
    /// True when the job asks launchd to keep it running (`KeepAlive`), so ending the process starts it again.
    public let keepAlive: Bool?
    public let runAtLoad: Bool?

    public init(plistPath: String?, keepAlive: Bool?, runAtLoad: Bool?) {
        self.plistPath = plistPath
        self.keepAlive = keepAlive
        self.runAtLoad = runAtLoad
    }
}

/// How a process came to be running.
public struct ProcessOrigin: Equatable, Codable, Sendable {
    public enum Kind: String, Codable, Sendable {
        /// It is the main process of a launchd job in the user's domain.
        case launchdJob
        /// It is an app opened through Launch Services (Dock, Finder, open).
        case application
        /// One of its ancestors is a launchd job or app; it was started by that.
        case descendant
        /// Its parent is launchd but it is not a job in the user's domain (a system daemon or an XPC service).
        case launchdOther
        /// Started by a shell, terminal or other process with no launchd job above it in the user's domain.
        case other
    }

    public let kind: Kind
    /// The job (its own, or the ancestor's).
    public let job: LaunchdJob?
    public let details: LaunchdJobDetails?
    /// The ancestor that is the job, for `.descendant`.
    public let viaPID: Int?

    public init(kind: Kind, job: LaunchdJob?, details: LaunchdJobDetails?, viaPID: Int?) {
        self.kind = kind
        self.job = job
        self.details = details
        self.viaPID = viaPID
    }

    public var summary: String {
        switch kind {
        case .launchdJob: return "Started by launchd job \(job?.label ?? "?")"
        case .application: return "Opened as an app (\(job?.bundleIdentifier ?? job?.label ?? "Launch Services"))"
        case .descendant:
            if let job, job.isApplication { return "Started by the app \(job.bundleIdentifier ?? job.label) (PID \(viaPID ?? 0))" }
            return "Started by launchd job \(job?.label ?? "?") (PID \(viaPID ?? 0))"
        case .launchdOther: return "Started by launchd, not as a job in your user session (a system service or XPC service)"
        case .other: return "Started from a shell, terminal or another program"
        }
    }
}

/// A file a process has open (`lsof -p PID`).
public struct OpenFile: Identifiable, Equatable, Codable, Sendable {
    public var id: String { descriptor + "|" + name }
    /// `cwd`, `txt`, `3`, `4u`…
    public let descriptor: String
    /// `REG`, `DIR`, `IPv4`, `unix`, `PIPE`…
    public let type: String
    public let name: String

    public init(descriptor: String, type: String, name: String) {
        self.descriptor = descriptor
        self.type = type
        self.name = name
    }

    public var isNetwork: Bool { type == "IPv4" || type == "IPv6" }
}

public struct OpenFilesReport: Equatable, Codable, Sendable {
    public let pid: Int
    public let files: [OpenFile]
    /// True when more were open than are listed.
    public let truncated: Bool
    public let note: String?

    public init(pid: Int, files: [OpenFile], truncated: Bool, note: String?) {
        self.pid = pid
        self.files = files
        self.truncated = truncated
        self.note = note
    }

    public var workingDirectory: String? { files.first { $0.descriptor == "cwd" }?.name }
}

/// Advice on whether ending a process is likely to be safe, with the reasons. Inference from facts MacPeek has
/// read, never a guarantee.
public struct KillAdvice: Equatable, Codable, Sendable {
    public enum Level: String, Codable, Sendable { case likelySafe, caution, avoid }
    public let level: Level
    public let reasons: [String]

    public init(level: Level, reasons: [String]) {
        self.level = level
        self.reasons = reasons
    }

    public var headline: String {
        switch level {
        case .likelySafe: return "Probably safe to end"
        case .caution: return "Check before ending"
        case .avoid: return "Avoid ending this"
        }
    }

    public static func assess(entry: ProcessEntry, snapshot: ProcessSnapshot, origin: ProcessOrigin?, currentUID: Int) -> KillAdvice {
        var reasons: [String] = []
        var level = Level.likelySafe
        func raise(_ to: Level) {
            let rank: [Level: Int] = [.likelySafe: 0, .caution: 1, .avoid: 2]
            if rank[to]! > rank[level]! { level = to }
        }
        if entry.pid <= 1 || entry.uid == 0 || entry.uid != currentUID {
            raise(.avoid)
            reasons.append(entry.uid == currentUID ? "It is a core system process." : "It belongs to \(entry.user), not you; macOS will not let you end it, and it is often a system service.")
        }
        if let warning = entry.sessionWarning {
            raise(.avoid)
            reasons.append(warning)
        }
        let children = snapshot.children(of: entry.pid)
        if !children.isEmpty {
            raise(.caution)
            reasons.append("It has \(children.count) child process\(children.count == 1 ? "" : "es"), which usually end with it or are left orphaned.")
        }
        switch origin?.kind {
        case .application?:
            raise(.caution)
            reasons.append("It is an app: quitting it from the app (⌘Q) lets it save its work first.")
        case .launchdJob?:
            if origin?.details?.keepAlive == true {
                raise(.caution)
                reasons.append("launchd keeps this job alive, so it will be started again right away. Unload the job instead to stop it for good.")
            } else {
                reasons.append("It is a launchd job (\(origin?.job?.label ?? "")); it may start again at next login or on demand.")
            }
        case .launchdOther?:
            raise(.caution)
            reasons.append("launchd started it as a service; services are usually restarted on demand.")
        case .descendant?:
            reasons.append(origin?.summary ?? "")
        case .other?, nil:
            break
        }
        if entry.state.first == "Z" {
            reasons.append("It is a zombie: it has already exited and only its parent can clear it.")
        }
        if reasons.isEmpty { reasons.append("Your own process, started from a terminal or another program, with no children.") }
        return KillAdvice(level: level, reasons: reasons.filter { !$0.isEmpty })
    }
}

/// `launchctl list`: `PID\tStatus\tLabel`, `-` when there is no PID.
public enum LaunchctlListParser {
    public static func parse(_ text: String) -> [LaunchdJob] {
        text.split(whereSeparator: \.isNewline).compactMap { line in
            let fields = line.split(separator: "\t", omittingEmptySubsequences: false).map { $0.trimmingCharacters(in: .whitespaces) }
            guard fields.count >= 3, fields[0] != "PID", !fields[2].isEmpty else { return nil }
            return LaunchdJob(label: fields[2], pid: Int(fields[0]), lastExitStatus: Int(fields[1]))
        }
    }
}

/// `launchctl print gui/<uid>/<label>`: `path = …` and the `properties = runatload | keepalive | …` line.
public enum LaunchctlPrintParser {
    public static func parse(_ text: String) -> LaunchdJobDetails? {
        var path: String?
        var properties: [String]?
        for raw in text.split(whereSeparator: \.isNewline) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if path == nil, line.hasPrefix("path = ") { path = String(line.dropFirst("path = ".count)) }
            if properties == nil, line.hasPrefix("properties = ") {
                properties = line.dropFirst("properties = ".count).split(separator: "|").map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
            }
        }
        guard path != nil || properties != nil else { return nil }
        return LaunchdJobDetails(plistPath: path, keepAlive: properties.map { $0.contains("keepalive") },
                                 runAtLoad: properties.map { $0.contains("runatload") })
    }
}

/// `lsof -n -P -p PID -F ftn`: field output, one record per file starting with `f`.
public enum LsofOpenFilesParser {
    public static func parse(_ text: String) -> [OpenFile] {
        var files: [OpenFile] = []
        var descriptor: String?
        var type = ""
        var name = ""
        func flush() {
            if let descriptor { files.append(OpenFile(descriptor: descriptor, type: type, name: LsofEscape.decode(name))) }
        }
        for raw in text.split(whereSeparator: \.isNewline) {
            guard let tag = raw.first else { continue }
            let value = String(raw.dropFirst())
            switch tag {
            case "f": flush(); descriptor = value; type = ""; name = ""
            case "t": type = value
            case "n": name = value
            default: break
            }
        }
        flush()
        return files
    }
}

public protocol ProcessInsightReading: Sendable {
    /// How the process was started: its launchd job, or the nearest ancestor's.
    func origin(of entry: ProcessEntry, in snapshot: ProcessSnapshot) async -> ProcessOrigin
    /// The files the process has open, read only when asked.
    func openFiles(of entry: ProcessEntry, limit: Int) async throws -> OpenFilesReport
}

/// `launchctl list` and `launchctl print` (read-only; MacPeek never loads, unloads or changes a job) and `lsof`.
public struct SystemProcessInsightReader: ProcessInsightReading {
    static let launchctl = "/bin/launchctl"
    static let lsof = "/usr/sbin/lsof"
    private let runner: CommandRunning
    private let uid: Int

    public init(runner: CommandRunning = ShellCommand(timeout: 15), uid: Int = Int(getuid())) {
        self.runner = runner
        self.uid = uid
    }

    public func origin(of entry: ProcessEntry, in snapshot: ProcessSnapshot) async -> ProcessOrigin {
        let jobs = (try? await runner.run(Self.launchctl, ["list"])).map { $0.status == 0 ? LaunchctlListParser.parse($0.stdout) : [] } ?? []
        let byPID = Dictionary(jobs.compactMap { job in job.pid.map { ($0, job) } }, uniquingKeysWith: { a, _ in a })
        if let job = byPID[entry.pid] {
            if job.isApplication { return ProcessOrigin(kind: .application, job: job, details: nil, viaPID: nil) }
            return ProcessOrigin(kind: .launchdJob, job: job, details: await details(of: job), viaPID: nil)
        }
        for ancestor in snapshot.ancestors(of: entry) {
            if let job = byPID[ancestor.pid] {
                return ProcessOrigin(kind: .descendant, job: job, details: nil, viaPID: ancestor.pid)
            }
        }
        if entry.ppid == 1 { return ProcessOrigin(kind: .launchdOther, job: nil, details: nil, viaPID: nil) }
        return ProcessOrigin(kind: .other, job: nil, details: nil, viaPID: nil)
    }

    /// Labels are passed as one argument (no shell); they must not start with `-` or contain `/` or whitespace.
    private static let labelPattern = NSRegularExpression.compile(#"^[A-Za-z0-9][^/\s]{0,250}$"#)

    private func details(of job: LaunchdJob) async -> LaunchdJobDetails? {
        guard Self.labelPattern.groups(in: job.label) != nil,
              let output = try? await runner.run(Self.launchctl, ["print", "gui/\(uid)/\(job.label)"]), output.status == 0 else { return nil }
        return LaunchctlPrintParser.parse(output.stdout)
    }

    /// The process's start time as `ps` reports it now, or nil when it has exited.
    private func startTime(pid: Int) async throws -> Date? {
        let output = try await runner.run("/usr/bin/env", ["LC_ALL=C", "/bin/ps", "-o", "lstart=", "-p", String(pid)])
        let line = output.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        guard output.status == 0, !line.isEmpty else { return nil }
        return PSParser.date(from: line)
    }

    /// Lists open files only while the PID still belongs to the process the person opened (same start time, checked
    /// before and after `lsof`), so a reused PID never shows another process's files.
    public func openFiles(of entry: ProcessEntry, limit: Int = 300) async throws -> OpenFilesReport {
        let changed = OpenFilesReport(pid: entry.pid, files: [], truncated: false,
                                      note: "This process has exited, or its PID now belongs to a different process.")
        guard PSProcessLister.sameProcess(try await startTime(pid: entry.pid), entry.startTime) else { return changed }
        let output = try await runner.run(Self.lsof, ["-n", "-P", "-w", "-p", String(entry.pid), "-F", "ftn"])
        guard PSProcessLister.sameProcess(try await startTime(pid: entry.pid), entry.startTime) else { return changed }
        let files = LsofOpenFilesParser.parse(output.stdout)
        if files.isEmpty {
            let note = entry.uid == uid ? "lsof listed no open files (the process may have exited)."
                                        : "macOS only shows the open files of your own processes."
            return OpenFilesReport(pid: entry.pid, files: [], truncated: false, note: note)
        }
        return OpenFilesReport(pid: entry.pid, files: Array(files.prefix(limit)), truncated: files.count > limit, note: nil)
    }
}
