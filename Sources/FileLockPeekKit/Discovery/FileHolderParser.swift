import Foundation
import MacPeekCore

/// Parses `lsof -F pcLftn` field output (p pid, c command, L login, f descriptor, t type, n name)
/// into holders grouped by process. Pure and deterministic.
public enum FileHolderParser {
    public static func parse(_ output: String, excludingPID: Int? = nil) -> [FileLockHolder] {
        struct Proc { var name: String; var user: String?; var files: [OpenFile] = [] }
        var order: [Int] = []
        var procs: [Int: Proc] = [:]

        var pid: Int?
        var command = ""
        var user: String?
        var inFile = false
        var descriptor: String?
        var type: String?
        var name: String?

        func flush() {
            defer { inFile = false; descriptor = nil; type = nil; name = nil }
            guard inFile, let pid, let descriptor, let name, !name.isEmpty, pid != excludingPID,
                  let file = makeFile(descriptor: descriptor, type: type, name: name)
            else { return }
            if procs[pid] == nil {
                procs[pid] = Proc(name: command.isEmpty ? "unknown" : command, user: user)
                order.append(pid)
            }
            if !procs[pid]!.files.contains(file) { procs[pid]!.files.append(file) }
        }

        for rawLine in output.split(whereSeparator: \.isNewline) {
            guard let tag = rawLine.first else { continue }
            let value = String(rawLine.dropFirst())
            switch tag {
            case "p":
                flush()
                pid = Int(value)
                command = ""
                user = nil
            case "c": command = LsofEscape.decode(value)
            case "L": user = value.isEmpty ? nil : value
            case "f": flush(); inFile = true; descriptor = value
            case "t": type = value
            case "n": name = LsofEscape.decode(value)
            default: break
            }
        }
        flush()

        return order.compactMap { pid -> FileLockHolder? in
            guard let p = procs[pid] else { return nil }
            let files = p.files.sorted { ($0.kind.priority, $0.path, $0.descriptor) < ($1.kind.priority, $1.path, $1.descriptor) }
            return FileLockHolder(pid: pid, processName: p.name, user: p.user, files: files)
        }
        .sorted { ($0.primaryKind.priority, $0.processName.lowercased(), $0.pid) < ($1.primaryKind.priority, $1.processName.lowercased(), $1.pid) }
    }

    /// Turns an lsof descriptor (`3r`, `5uW`, `cwd`, `txt`, `mem`, …) into a kind and optional lock text.
    static func makeFile(descriptor: String, type: String?, name: String) -> OpenFile? {
        let kind: HoldKind
        var lock: String?
        switch descriptor {
        case "cwd": kind = .workingDirectory
        case "txt": kind = .executable
        case "mem": kind = .memoryMapped
        case "rtd": return nil // every process has a root directory; never interesting
        default:
            let rest = descriptor.drop(while: \.isNumber)
            if rest.count < descriptor.count, let mode = rest.first { // numeric fd followed by access mode
                switch mode {
                case "r": kind = .open(.read)
                case "w": kind = .open(.write)
                case "u": kind = .open(.readWrite)
                default: kind = .other(descriptor)
                }
                if let lockChar = rest.dropFirst().first { lock = lockText(lockChar) }
            } else {
                kind = .other(descriptor)
            }
        }
        return OpenFile(path: name, descriptor: descriptor, kind: kind, lock: lock, fileType: type)
    }

    private static func lockText(_ c: Character) -> String? {
        switch c {
        case "r": return "read lock (part of file)"
        case "R": return "read lock (whole file)"
        case "w": return "write lock (part of file)"
        case "W": return "write lock (whole file)"
        case "x", "X": return "exclusive lock"
        case "u": return "lock (type unknown)"
        case " ": return nil
        default: return nil
        }
    }
}
