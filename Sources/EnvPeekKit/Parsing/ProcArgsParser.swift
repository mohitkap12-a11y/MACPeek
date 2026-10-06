import Foundation

/// Parses the buffer returned by `sysctl(KERN_PROCARGS2)`:
///
///     int32 argc | exec_path\0 | \0 padding… | argv[0]\0 … argv[argc-1]\0 | env[0]\0 env[1]\0 …
///
/// Pure function over bytes, so it is unit-tested without touching a real process.
public enum ProcArgsParser {
    public static func parse(_ bytes: [UInt8]) -> ProcessArguments? {
        guard bytes.count > MemoryLayout<Int32>.size else { return nil }
        // argc is a native-endian Int32 at the start of the buffer.
        var argc: Int32 = 0
        withUnsafeMutableBytes(of: &argc) { destination in
            for index in 0..<MemoryLayout<Int32>.size { destination[index] = bytes[index] }
        }
        guard argc >= 0, argc < 100_000 else { return nil }

        var cursor = MemoryLayout<Int32>.size
        func nextString() -> String? {
            guard cursor < bytes.count else { return nil }
            var end = cursor
            while end < bytes.count && bytes[end] != 0 { end += 1 }
            let text = String(decoding: bytes[cursor..<end], as: UTF8.self)
            cursor = min(end + 1, bytes.count)
            return text
        }

        let executable = nextString()
        // Skip the NUL padding that follows the executable path.
        while cursor < bytes.count && bytes[cursor] == 0 { cursor += 1 }

        var arguments: [String] = []
        for _ in 0..<Int(argc) {
            guard let argument = nextString() else { break }
            arguments.append(argument)
        }

        var environment: [EnvVariable] = []
        var seen: [String: Int] = [:]
        while let entry = nextString() {
            if entry.isEmpty { break }  // the environment block ends at the first empty string
            guard let equals = entry.firstIndex(of: "=") else { continue }
            let name = String(entry[entry.startIndex..<equals])
            guard !name.isEmpty else { continue }
            let occurrence = seen[name, default: 0]
            seen[name] = occurrence + 1
            environment.append(EnvVariable(name: name, value: String(entry[entry.index(after: equals)...]), occurrence: occurrence))
        }
        return ProcessArguments(executable: executable, arguments: arguments, environment: environment)
    }
}
