#if os(macOS)
import SwiftUI

/// A compact label/value table used in detail panels.
struct KeyValueRows: View {
    let rows: [(label: String, value: String)]

    var body: some View {
        Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 4) {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                GridRow {
                    Text(row.label).foregroundStyle(.secondary)
                    Text(row.value).textSelection(.enabled)
                }
            }
        }
        .font(.caption)
    }
}
#endif
