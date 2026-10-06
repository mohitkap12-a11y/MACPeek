import Foundation

/// Parses `pmset -g assertions` (format verified against a real Mac):
///
///     Assertion status system-wide:
///        PreventUserIdleSystemSleep     1
///     Listed by owning process:
///        pid 4647(bluetoothd): [0x00018c2b00018fb8] 00:01:49 PreventUserIdleSystemSleep named: "com.apple.BTStack"
///     	Timeout will fire in 600 secs Action=TimeoutActionRelease
///     Kernel Assertions: 0x104=USB,MAGICWAKE
///        id=537  level=255 0x4=USB creat= description=com.apple.usb.externaldevice.02100000 owner=USB3.1 Hub
public enum AssertionParser {
    private enum Section { case none, status, processes, kernel }

    private static let statusLine = NSRegularExpression.compile(#"^\s+(\S+)\s+(\d+)\s*$"#)
    private static let processLine = NSRegularExpression.compile(
        #"^\s*pid (\d+)\((.+?)\): \[(0x[0-9a-fA-F]+)\] (\d+:\d+:\d+) (\S+) named: "(.*)"\s*$"#)
    private static let kernelLine = NSRegularExpression.compile(#"id=(\d+)\s+level=\d+.*?description=(.*?)\s+owner=(.*)$"#)

    public static func parse(_ text: String) -> AssertionReport {
        var section = Section.none
        var status: [(name: String, count: Int)] = []
        var assertions: [SleepAssertion] = []
        var kernel: [KernelAssertion] = []

        for rawLine in text.split(separator: "\n", omittingEmptySubsequences: true).map(String.init) {
            let trimmed = rawLine.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("Assertion status system-wide") { section = .status; continue }
            if trimmed.hasPrefix("Listed by owning process") { section = .processes; continue }
            if trimmed.hasPrefix("Kernel Assertions") { section = .kernel; continue }

            switch section {
            case .none:
                continue
            case .status:
                if let g = statusLine.groups(in: rawLine), let name = g[1], let count = g[2].flatMap({ Int($0) }) {
                    status.append((name, count))
                }
            case .processes:
                if let g = processLine.groups(in: rawLine), let pid = g[1].flatMap({ Int($0) }) {
                    assertions.append(SleepAssertion(
                        id: g[3] ?? "\(pid)-\(assertions.count)", pid: pid, processName: g[2] ?? "", type: g[5] ?? "",
                        name: g[6] ?? "", heldFor: g[4] ?? ""))
                } else if !trimmed.isEmpty, let last = assertions.last, rawLine.first?.isWhitespace == true {
                    assertions[assertions.count - 1] = SleepAssertion(
                        id: last.id, pid: last.pid, processName: last.processName, type: last.type, name: last.name,
                        heldFor: last.heldFor, details: last.details + [trimmed])
                }
            case .kernel:
                if let g = kernelLine.groups(in: rawLine), let id = g[1].flatMap({ Int($0) }) {
                    kernel.append(KernelAssertion(
                        id: id,
                        description: (g[2] ?? "").trimmingCharacters(in: .whitespaces),
                        owner: (g[3] ?? "").trimmingCharacters(in: .whitespaces)))
                }
            }
        }
        return AssertionReport(systemStatus: status, assertions: assertions, kernelAssertions: kernel)
    }
}
