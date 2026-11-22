#if os(macOS)
import SwiftUI

/// One coloured part of a `RingGauge`, as a fraction of the full circle.
struct RingSegment {
    let fraction: Double
    let color: Color
}

/// A circular gauge. Each segment is a fraction of the full circle, drawn one after another from the top.
struct RingGauge<Center: View>: View {
    let segments: [RingSegment]
    var lineWidth: CGFloat = 7
    var roundedEnds = true
    @ViewBuilder let center: () -> Center

    var body: some View {
        ZStack {
            Circle().stroke(PeekTheme.track, lineWidth: lineWidth)
            ForEach(Array(arcs.enumerated()), id: \.offset) { _, arc in
                Circle()
                    .trim(from: arc.start, to: arc.end)
                    .stroke(arc.color, style: StrokeStyle(lineWidth: lineWidth, lineCap: roundedEnds && segments.count == 1 ? .round : .butt))
                    .rotationEffect(.degrees(-90))
            }
            center()
        }
        .padding(lineWidth / 2)
    }

    private var arcs: [(start: CGFloat, end: CGFloat, color: Color)] {
        var start = 0.0
        return segments.compactMap { segment in
            let fraction = min(max(segment.fraction, 0), 1 - start)
            defer { start += fraction }
            return fraction > 0 ? (CGFloat(start), CGFloat(start + fraction), segment.color) : nil
        }
    }
}

extension RingGauge {
    init(fraction: Double, color: Color, lineWidth: CGFloat = 7, @ViewBuilder center: @escaping () -> Center) {
        self.init(segments: [RingSegment(fraction: fraction, color: color)], lineWidth: lineWidth, center: center)
    }
}

/// An area chart of recent values (oldest first), scaled to `maximum`. Used for "since opened" history.
struct HistoryChart: View {
    struct Series {
        let values: [Double]
        let color: Color
        var filled = true
        /// Time of each value, for the hover readout.
        var times: [Date] = []
        var name: String? = nil
    }

    let series: [Series]
    let maximum: Double
    /// Formats a value for the hover readout; hover is off when nil.
    var format: ((Double) -> String)? = nil
    @State private var hover: CGFloat?

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .topLeading) {
                ForEach(Array(series.enumerated()), id: \.offset) { _, line in
                    if line.filled {
                        area(line.values, in: proxy.size).fill(line.color.opacity(0.2))
                    }
                    path(line.values, in: proxy.size).stroke(line.color, lineWidth: 1.5)
                }
                if let format, let x = hover, let first = series.first, first.values.count > 1 {
                    let fraction = min(max(x / max(proxy.size.width, 1), 0), 1)
                    let index = Int((fraction * CGFloat(first.values.count - 1)).rounded())
                    let px = CGFloat(index) * proxy.size.width / CGFloat(first.values.count - 1)
                    Path { p in
                        p.move(to: CGPoint(x: px, y: 0))
                        p.addLine(to: CGPoint(x: px, y: proxy.size.height))
                    }
                    .stroke(Color.secondary.opacity(0.6), lineWidth: 1)
                    let label = tooltip(index: index, format: format)
                    Text(label)
                        .font(.system(size: 10.5, weight: .medium).monospacedDigit())
                        .padding(.horizontal, 6).padding(.vertical, 3)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 5))
                        .fixedSize()
                        .position(x: min(max(px, 70), max(proxy.size.width - 70, 70)), y: 10)
                        .allowsHitTesting(false)
                }
            }
            .contentShape(Rectangle())
            .onContinuousHover { phase in
                switch phase {
                case .active(let location): hover = location.x
                case .ended: hover = nil
                }
            }
        }
        .accessibilityHidden(true)
    }

    private func tooltip(index: Int, format: (Double) -> String) -> String {
        var lines: [String] = []
        if let time = series.first(where: { $0.times.indices.contains(index) })?.times[index] {
            lines.append(time.formatted(date: .omitted, time: .standard))
        }
        for line in series where line.values.indices.contains(index) {
            let value = format(line.values[index])
            lines.append(line.name.map { "\($0) \(value)" } ?? value)
        }
        return lines.joined(separator: " · ")
    }

    private func points(_ values: [Double], in size: CGSize) -> [CGPoint] {
        guard values.count > 1, maximum > 0 else { return [] }
        let step = size.width / CGFloat(values.count - 1)
        return values.enumerated().map { index, value in
            CGPoint(x: CGFloat(index) * step, y: size.height - size.height * CGFloat(min(max(value / maximum, 0), 1)))
        }
    }

    private func path(_ values: [Double], in size: CGSize) -> Path {
        Path { path in
            let pts = points(values, in: size)
            guard let first = pts.first else { return }
            path.move(to: first)
            for point in pts.dropFirst() { path.addLine(to: point) }
        }
    }

    private func area(_ values: [Double], in size: CGSize) -> Path {
        Path { path in
            let pts = points(values, in: size)
            guard let first = pts.first, let last = pts.last else { return }
            path.move(to: CGPoint(x: first.x, y: size.height))
            for point in pts { path.addLine(to: point) }
            path.addLine(to: CGPoint(x: last.x, y: size.height))
            path.closeSubpath()
        }
    }
}

/// A horizontal bar split into coloured parts (fractions of the whole).
struct SegmentedBar: View {
    struct Part {
        let fraction: Double
        let color: Color
    }

    let parts: [Part]
    var height: CGFloat = 10

    var body: some View {
        GeometryReader { proxy in
            HStack(spacing: 2) {
                ForEach(Array(parts.enumerated()), id: \.offset) { _, part in
                    Rectangle().fill(part.color)
                        .frame(width: max(proxy.size.width - CGFloat(parts.count - 1) * 2, 0) * CGFloat(min(max(part.fraction, 0), 1)))
                }
            }
        }
        .frame(height: height)
        .background(PeekTheme.track)
        .clipShape(Capsule())
        .accessibilityHidden(true)
    }
}

/// A half-circle gauge with green, amber and red zones and a needle at `level` (0 = far left, 1 = far right).
struct PressureGauge: View {
    let level: Double?

    var body: some View {
        Canvas { context, size in
            let center = CGPoint(x: size.width / 2, y: size.height - 8)
            let radius = min(size.width / 2, size.height) - 10
            // Angles in degrees above the horizontal: 180 is the far left, 0 the far right. Drawn point by point so the
            // direction never depends on the coordinate system's orientation.
            let zones: [(Double, Double, Color)] = [(180, 128, PeekTheme.green), (122, 58, PeekTheme.amber), (52, 0, PeekTheme.red)]
            for (from, to, color) in zones {
                var arc = Path()
                let steps = 24
                for step in 0...steps {
                    let degrees = from + (to - from) * Double(step) / Double(steps)
                    let radians = degrees * .pi / 180
                    let point = CGPoint(x: center.x + CGFloat(cos(radians)) * radius, y: center.y - CGFloat(sin(radians)) * radius)
                    if step == 0 { arc.move(to: point) } else { arc.addLine(to: point) }
                }
                context.stroke(arc, with: .color(color), style: StrokeStyle(lineWidth: 9, lineCap: .round))
            }
            guard let level else { return }
            let angle = Double.pi * (1 - min(max(level, 0), 1))
            let tip = CGPoint(x: center.x + CGFloat(cos(angle)) * (radius - 12), y: center.y - CGFloat(sin(angle)) * (radius - 12))
            var needle = Path()
            needle.move(to: center)
            needle.addLine(to: tip)
            context.stroke(needle, with: .foreground, style: StrokeStyle(lineWidth: 3, lineCap: .round))
            context.fill(Path(ellipseIn: CGRect(x: center.x - 5, y: center.y - 5, width: 10, height: 10)), with: .foreground)
        }
        .accessibilityHidden(true)
    }
}

/// A fixed-size ring of recent values: the history behind the "since opened" charts.
struct RecentValues: Equatable {
    private(set) var values: [Double] = []
    let capacity: Int

    init(capacity: Int = 60) {
        self.capacity = capacity
    }

    mutating func append(_ value: Double) {
        values.append(value)
        if values.count > capacity { values.removeFirst(values.count - capacity) }
    }

    mutating func removeAll() { values.removeAll() }
}
#endif
