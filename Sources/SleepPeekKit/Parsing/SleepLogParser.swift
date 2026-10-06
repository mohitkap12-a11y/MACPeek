import Foundation

/// Parses sleep/wake events out of `pmset -g log`.
///
/// Each log line is `2026-10-06 18:25:07 +0530 <Kind><whitespace><message>`. Only the `Sleep`, `Wake` and
/// `DarkWake` kinds are read (other kinds, like client acknowledgements, are noise for this purpose), and the
/// "due to …" text is kept exactly as macOS wrote it, never reinterpreted.
public enum SleepLogParser {
    private static let timestamp = NSRegularExpression.compile(#"^(\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}) ([+-]\d{4}) (.*)$"#)
    private static let kindSplit = NSRegularExpression.compile(#"^(.*?)(?:\t+|\s{2,})(.*)$"#)
    private static let reason = NSRegularExpression.compile(#"due to (.*?)(?: Using (AC|Batt|BATT|UPS)\b.*)?\s*$"#)
    private static let wakeRequest = NSRegularExpression.compile(
        #"\[\*?process=(.+?) request=(.+?) deltaSecs=\d+ wakeAt=(\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}) info="(.*?)"\]"#)

    public static func parse(_ text: String, limit: Int = 60) -> SleepHistory {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss Z"

        var events: [SleepEvent] = []
        var latestRequests: (line: String, zone: String, recorded: Date?)?

        for line in text.split(separator: "\n", omittingEmptySubsequences: true) {
            // Cheap pre-filter: the log can be tens of thousands of lines.
            guard line.first?.isNumber == true else { continue }
            let line = String(line)
            guard let t = timestamp.groups(in: line), let stamp = t[1], let zone = t[2], let rest = t[3],
                  let date = formatter.date(from: "\(stamp) \(zone)"),
                  let k = kindSplit.groups(in: rest), let kindText = k[1], let message = k[2] else { continue }

            if kindText == "Wake Requests" {
                latestRequests = (message, zone, date)
                continue
            }
            guard let kind = SleepEvent.Kind(rawValue: kindText) else { continue }
            let r = reason.groups(in: message)
            events.append(SleepEvent(
                date: date, kind: kind,
                reason: r?[1].flatMap { $0.isEmpty ? nil : $0 },
                powerSource: r?[2].map { $0.uppercased() == "BATT" ? "Batt" : $0.uppercased() },
                raw: message.trimmingCharacters(in: .whitespaces), index: events.count))
        }

        var requests: [WakeRequest] = []
        if let latest = latestRequests {
            for (index, g) in wakeRequest.allGroups(in: latest.line).enumerated() {
                requests.append(WakeRequest(
                    process: g[1] ?? "", request: g[2] ?? "",
                    wakeAt: g[3].flatMap { formatter.date(from: "\($0) \(latest.zone)") },
                    info: g[4] ?? "", index: index))
            }
        }
        return SleepHistory(events: Array(events.suffix(limit).reversed()), wakeRequests: requests,
                            wakeRequestsRecordedAt: latestRequests?.recorded)
    }
}
