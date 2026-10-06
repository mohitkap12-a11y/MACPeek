#if os(macOS)
import SwiftUI

/// Title bar used by every MacPeek screen: optional back button, title, optional trailing controls.
struct PeekHeader<Trailing: View>: View {
    let title: String
    let subtitle: String?
    let onBack: (() -> Void)?
    let trailing: Trailing

    init(title: String, subtitle: String? = nil, onBack: (() -> Void)? = nil,
         @ViewBuilder trailing: () -> Trailing) {
        self.title = title
        self.subtitle = subtitle
        self.onBack = onBack
        self.trailing = trailing()
    }

    var body: some View {
        HStack(spacing: 8) {
            if let onBack {
                Button(action: onBack) { Image(systemName: "chevron.left").fontWeight(.semibold) }
                    .help("Back")
                    .keyboardShortcut("[", modifiers: .command)
                    .accessibilityLabel("Back")
            }
            VStack(alignment: .leading, spacing: 0) {
                Text(title).font(.system(size: 14, weight: .semibold))
                if let subtitle {
                    Text(subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)
            Spacer()
            trailing
        }
        .buttonStyle(.borderless)
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
    }
}

extension PeekHeader where Trailing == EmptyView {
    init(title: String, subtitle: String? = nil, onBack: (() -> Void)? = nil) {
        self.init(title: title, subtitle: subtitle, onBack: onBack) { EmptyView() }
    }
}
#endif
