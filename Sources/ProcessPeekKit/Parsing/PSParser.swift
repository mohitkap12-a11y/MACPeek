import Foundation

/// Parses `ps -axo pid,ppid,uid,user,state,lstart,etime,%cpu,rss,comm` (format verified against a real Mac).
///
///       PID  PPID   UID USER             STAT STARTED                          ELAPSED  %CPU    RSS COMM
///         1     0     0 root             Ss   Mon Oct  5 14:01:58 2026     01-05:36:20   0.0   4880 /sbin/launchd
///
/// `comm` is last because executable paths can contain spaces; `lstart` is five tokens.
public enum PSParser {
    private static let row = NSRegularExpression.compile(
        #"^\s*(\d+)\s+(\d+)\s+(-?\d+)\s+(\S+)\s+(\S+)\s+([A-Z][a-z]{2} [A-Z][a-z]{2}\s+\d{1,2} \d{2}:\d{2}:\d{2} \d{4})\s+(\S+)\s+([0-9.]+)\s+(\d+)\s+(.+?)\s*$"#)

    public static func parse(_ text: String) -> [ProcessEntry] {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "EEE MMM d HH:mm:ss yyyy"  // `ps` prints local time

        return text.split(separator: "\n", omittingEmptySubsequences: true).compactMap { line in
            guard let g = row.groups(in: String(line)),
                  let pid = g[1].flatMap({ Int($0) }), let ppid = g[2].flatMap({ Int($0) }),
                  let uid = g[3].flatMap({ Int($0) }), let user = g[4], let state = g[5],
                  let started = g[6], let elapsed = g[7],
                  let cpu = g[8].flatMap({ Double($0) }), let rss = g[9].flatMap({ Int($0) }),
                  let command = g[10], !command.isEmpty else { return nil }
            // "Mon Oct  5 14:01:58 2026" has two spaces for single-digit days.
            let normalized = started.split(whereSeparator: \.isWhitespace).joined(separator: " ")
            return ProcessEntry(pid: pid, ppid: ppid, uid: uid, user: user, state: state,
                                startTime: formatter.date(from: normalized), elapsed: elapsed,
                                cpuPercent: cpu, residentKB: rss, executable: command)
        }
    }
}
