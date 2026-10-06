import Foundation

/// A statement SleepPeek makes, labelled by where it comes from, so facts are never blurred with guesses.
public struct Finding: Equatable, Sendable {
    public enum Basis: Sendable {
        /// Read directly from macOS output.
        case verified
        /// A common explanation for what macOS reported. Plausible, not proven.
        case inference
    }
    public let basis: Basis
    public let text: String

    public init(_ basis: Basis, _ text: String) {
        self.basis = basis
        self.text = text
    }
}

/// An assertion that keeps the Mac (or its display) awake, with what is known and what is merely likely.
public struct SleepBlocker: Identifiable, Equatable, Sendable {
    public var id: String { assertion.id }
    public let assertion: SleepAssertion
    public let findings: [Finding]

    public init(assertion: SleepAssertion, findings: [Finding]) {
        self.assertion = assertion
        self.findings = findings
    }
}

public struct SleepDiagnosis: Equatable, Sendable {
    /// From macOS's own system-wide counters.
    public let systemSleepBlocked: Bool
    public let displaySleepBlocked: Bool
    /// Recent user input is registered (a `UserIsActive` assertion), which also keeps the Mac awake.
    public let userActive: Bool
    /// Blocking assertions, those holding the whole system awake first.
    public let blockers: [SleepBlocker]
    /// Holds macOS itself takes while the display is on (powerd's "Prevent sleep while display is on"). They
    /// are listed for completeness but do not count as something to chase down.
    public let expectedHolds: [SleepBlocker]
    /// macOS's own statement from `pmset -g` of who is preventing sleep (verified).
    public let macOSReportedBlockers: [String]

    public init(systemSleepBlocked: Bool, displaySleepBlocked: Bool, userActive: Bool,
                blockers: [SleepBlocker], expectedHolds: [SleepBlocker] = [], macOSReportedBlockers: [String]) {
        self.systemSleepBlocked = systemSleepBlocked
        self.displaySleepBlocked = displaySleepBlocked
        self.userActive = userActive
        self.blockers = blockers
        self.expectedHolds = expectedHolds
        self.macOSReportedBlockers = macOSReportedBlockers
    }

    public var headline: String {
        if systemSleepBlocked { return "Something is keeping your Mac awake" }
        if displaySleepBlocked { return "Something is keeping the display awake" }
        if !expectedHolds.isEmpty { return "Your Mac stays awake while the display is on" }
        if userActive { return "Your Mac is awake because you are using it" }
        return "Nothing is blocking sleep right now"
    }
}

public enum SleepAnalysis {
    public static func diagnose(report: AssertionReport, settings: PowerSettings?) -> SleepDiagnosis {
        let all = report.assertions
            .filter(\.blocksSleep)
            .sorted { lhs, rhs in
                if lhs.preventsSystemSleep != rhs.preventsSystemSleep { return lhs.preventsSystemSleep }
                return lhs.processName.lowercased() < rhs.processName.lowercased()
            }
            .map { SleepBlocker(assertion: $0, findings: findings(for: $0)) }
        let expected = all.filter { isExpectedWhileDisplayOn($0.assertion) }
        let blockers = all.filter { !isExpectedWhileDisplayOn($0.assertion) }

        // macOS's counters decide "blocked"; the per-process list only explains it. Holds that are expected
        // while the display is on are subtracted from the counters so they alone never raise the alarm.
        let systemCount = SleepAssertionTypes.system.reduce(0) { $0 + report.count($1) }
        let expectedSystem = expected.filter { $0.assertion.preventsSystemSleep }.count
        let systemBlocked = systemCount > expectedSystem || blockers.contains { $0.assertion.preventsSystemSleep }
        let displayBlocked = SleepAssertionTypes.display.contains { report.count($0) > 0 } || blockers.contains { $0.assertion.preventsDisplaySleep }
        let active = report.count("UserIsActive") > 0 || report.assertions.contains { $0.type == "UserIsActive" }

        return SleepDiagnosis(
            systemSleepBlocked: systemBlocked, displaySleepBlocked: displayBlocked, userActive: active,
            blockers: blockers, expectedHolds: expected, macOSReportedBlockers: settings?.preventedBy["sleep"] ?? [])
    }

    /// powerd's own assertion while the display is on: normal, and released when the display sleeps.
    static func isExpectedWhileDisplayOn(_ assertion: SleepAssertion) -> Bool {
        assertion.processName.lowercased() == "powerd" && assertion.name.lowercased().contains("display is on")
    }

    /// Verified facts first, then at most one clearly labelled inference from a small, conservative table.
    static func findings(for assertion: SleepAssertion) -> [Finding] {
        let named = assertion.name.isEmpty ? "" : " “" + assertion.name + "”"
        var result = [Finding(.verified,
            "\(assertion.processName) (PID \(assertion.pid)) holds \(assertion.type)\(named), for \(assertion.heldFor).")]
        for detail in assertion.details { result.append(Finding(.verified, detail)) }

        let process = assertion.processName.lowercased()
        let name = assertion.name.lowercased()
        if process == "powerd" && name.contains("display is on") {
            result.append(Finding(.inference, "Normal while the display is on. It is released once the display sleeps."))
        } else if process == "caffeinate" {
            result.append(Finding(.inference, "Likely started by a caffeinate command, from a Terminal session, script or app."))
        } else if process == "coreaudiod" || name.contains("audio") {
            result.append(Finding(.inference, "Usually held while audio is playing or recording."))
        } else if process == "backupd" || name.contains("time machine") {
            result.append(Finding(.inference, "Likely a Time Machine backup in progress."))
        }
        return result
    }
}

public extension SleepDiagnosis {
    /// Plain text for a support thread or a bug report. Facts and inferences stay labelled.
    var copyText: String {
        var lines = [headline]
        if !macOSReportedBlockers.isEmpty { lines.append("macOS reports sleep is prevented by: \(macOSReportedBlockers.joined(separator: ", "))") }
        for blocker in blockers + expectedHolds {
            lines.append("")
            for finding in blocker.findings {
                lines.append("[\(finding.basis == .verified ? "reported by macOS" : "inference")] \(finding.text)")
            }
        }
        return lines.joined(separator: "\n")
    }
}
