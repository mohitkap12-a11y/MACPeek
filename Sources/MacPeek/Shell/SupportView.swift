#if os(macOS)
import SwiftUI

/// Where to send people who want to support MacPeek. Keep in sync with `SITE` in MACPeek-Web/src/site.ts.
enum SupportLinks {
    static let github = URL(string: "https://github.com/mohitkap12-a11y/MACPeek")!
    static let sponsorGithub = URL(string: "https://github.com/sponsors/mohitkap12-a11y")!
    static let sponsorPaypal = URL(string: "https://paypal.me/mkapoor91")!
}

/// A gentle, optional ask: MacPeek is free and open source, and nothing is gated behind it.
struct SupportView: View {
    @EnvironmentObject private var router: UtilityRouter

    var body: some View {
        VStack(spacing: 0) {
            PeekHeader(title: "Support MacPeek", onBack: { router.backFromSupport() })
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text("MacPeek is free and open source.").font(.headline)
                    Text("If it saves you time, you can help keep it maintained and growing. Entirely optional, and nothing in the app depends on it.")
                        .font(.callout).foregroundStyle(.secondary)
                    supportCard(
                        symbol: "heart.fill", title: "Sponsor on GitHub",
                        detail: "Recurring or one-time support through GitHub Sponsors.",
                        url: SupportLinks.sponsorGithub)
                    supportCard(
                        symbol: "creditcard", title: "Donate with PayPal",
                        detail: "A one-time contribution of any amount.",
                        url: SupportLinks.sponsorPaypal)
                    supportCard(
                        symbol: "star", title: "Star or contribute on GitHub",
                        detail: "A star, a bug report or a pull request helps just as much.",
                        url: SupportLinks.github)
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func supportCard(symbol: String, title: String, detail: String, url: URL) -> some View {
        Link(destination: url) {
            HStack(spacing: 10) {
                Image(systemName: symbol).font(.system(size: 16)).frame(width: 24)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.system(size: 13, weight: .semibold))
                    Text(detail).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "arrow.up.right").font(.caption).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .peekCard()
        .accessibilityLabel("\(title). \(detail)")
    }
}
#endif
