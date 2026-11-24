#if os(macOS)
import SwiftUI

struct EmptyState: View {
    let symbol: String
    let title: String
    var message: String? = nil
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: symbol).font(.system(size: 28)).foregroundStyle(PeekTheme.muted).accessibilityHidden(true)
            Text(title).font(.system(size: 13, weight: .semibold))
            if let message {
                Text(message).font(.system(size: 12)).foregroundStyle(PeekTheme.muted).multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true).frame(maxWidth: 280)
            }
            if let actionTitle, let action {
                Button(actionTitle, action: action).buttonStyle(.borderedProminent).controlSize(.regular).padding(.top, 8)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .contain)
    }
}

struct ErrorState: View {
    let message: String
    var retryTitle: String = "Retry"
    let retry: () -> Void

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle").font(.system(size: 26)).foregroundStyle(.orange).accessibilityHidden(true)
            Text("Unable to read system information").font(.callout)
            Text(message).font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center).lineLimit(3)
            Button(retryTitle, action: retry)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
#endif
