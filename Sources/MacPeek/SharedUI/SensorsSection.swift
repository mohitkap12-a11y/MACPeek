#if os(macOS)
import SwiftUI
import SensorsKit

/// Temperatures (hottest and average per part of the chip), fans and whole-Mac power, as the Mac shares them. Sensors
/// are read through interfaces Apple does not document; when a Mac shares none the section says so in one line.
struct SensorsSection: View {
    let snapshot: SensorSnapshot?
    /// Which groups to show; nil for all of them.
    var groups: Set<SensorGroup>? = nil
    var showsFans = true
    var showsPower = true
    @State private var showAll = false

    private var summary: [SensorSummary] {
        (snapshot?.summary ?? []).filter { groups?.contains($0.group) ?? true }
    }

    var body: some View {
        if let snapshot {
            let fans = showsFans ? snapshot.fans : []
            let watts = showsPower ? snapshot.systemWatts : nil
            if summary.isEmpty && fans.isEmpty && watts == nil {
                if groups == nil, let note = snapshot.note {
                    VStack(alignment: .leading, spacing: 6) {
                        SectionLabel(text: "Temperatures")
                        Text(note).font(.caption).foregroundStyle(PeekTheme.muted)
                    }
                }
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    SectionLabel(text: "Temperatures", trailing: summary.isEmpty ? nil : "hottest · average")
                    ForEach(summary) { item in
                        DetailRow(label: item.count > 1 ? "\(item.group.title) (\(item.count) sensors)" : item.group.title,
                                  value: "\(Self.celsius(item.hottest)) · \(Self.celsius(item.average))",
                                  dot: Self.color(item.hottest))
                    }
                    if showAll {
                        ForEach(snapshot.temperatures.filter { groups?.contains($0.group) ?? true }) { sensor in
                            DetailRow(label: sensor.name, value: Self.celsius(sensor.celsius))
                                .font(.system(size: 11))
                        }
                    }
                    ForEach(fans) { fan in
                        VStack(alignment: .leading, spacing: 3) {
                            DetailRow(label: fans.count > 1 ? "Fan \(fan.index + 1)" : "Fan", value: Self.rpm(fan))
                            if let fraction = fan.fraction {
                                SegmentedBar(parts: [.init(fraction: fraction, color: PeekTheme.accent)], height: 5)
                            }
                        }
                    }
                    if let watts {
                        DetailRow(label: "Mac power draw", value: String(format: "%.1f W", watts))
                    }
                    HStack {
                        Text("Read from the Mac's sensors through interfaces Apple does not document.")
                        Spacer(minLength: 4)
                        if !summary.isEmpty {
                            Button(showAll ? "Fewer" : "All sensors") { showAll.toggle() }.buttonStyle(.borderless)
                        }
                    }
                    .font(.system(size: 10.5))
                    .foregroundStyle(PeekTheme.muted)
                }
            }
        }
    }

    static func celsius(_ value: Double) -> String { "\(Int(value.rounded())) °C" }

    static func rpm(_ fan: FanReading) -> String {
        fan.rpm < 1 ? "Stopped" : "\(Int(fan.rpm.rounded())) rpm"
    }

    static func color(_ celsius: Double) -> Color {
        celsius >= 95 ? PeekTheme.red : celsius >= 85 ? PeekTheme.amber : PeekTheme.green
    }
}
#endif
