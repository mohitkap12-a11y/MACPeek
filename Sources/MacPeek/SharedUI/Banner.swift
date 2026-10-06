#if os(macOS)
import SwiftUI

/// A transient result message ("✓ Port 3000 freed", an error, …) shown under a utility's header.
struct Banner: Equatable {
    enum Kind { case success, error }
    let kind: Kind
    let text: String
}

struct BannerView: View {
    let banner: Banner
    var body: some View {
        Text(banner.text)
            .font(.caption)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background((banner.kind == .success ? Color.green : Color.red).opacity(0.15))
            .transition(.opacity)
            .accessibilityAddTraits(.updatesFrequently)
    }
}
#endif
