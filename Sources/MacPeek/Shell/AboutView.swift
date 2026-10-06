#if os(macOS)
import SwiftUI

struct AboutView: View {
    @EnvironmentObject private var router: UtilityRouter

    private var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "development build"
    }

    var body: some View {
        VStack(spacing: 0) {
            PeekHeader(title: "About MacPeek", onBack: { router.back() })
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text("MacPeek").font(.system(size: 22, weight: .bold))
                    Text("The tiny utilities macOS should have built in.").foregroundStyle(.secondary)
                    Text("Version \(version)").font(.caption).foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Private by design").font(.headline)
                        Text("No account. No telemetry. No cloud. MacPeek reads information from your Mac to show it to you and never sends it anywhere.")
                            .font(.callout)
                    }
                    .peekCard()
                    Link("MacPeek on GitHub", destination: URL(string: "https://github.com/mohitkap12-a11y/MACPeek")!)
                    Text("Open source under the MIT License. macOS is a trademark of Apple Inc.; MacPeek is not affiliated with Apple.")
                        .font(.caption2).foregroundStyle(.secondary)
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}
#endif
