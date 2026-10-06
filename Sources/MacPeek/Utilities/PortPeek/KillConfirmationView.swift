#if os(macOS)
import SwiftUI
import MacPeekCore
import PortPeekKit

/// Inline confirmation used for both graceful termination and the explicit force-kill step.
struct KillConfirmationView: View {
    let port: PortInfo
    let title: String
    let confirmLabel: String
    let destructive: Bool
    let onCancel: () -> Void
    let onConfirm: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Text(title).font(.system(size: 12, weight: .medium)).lineLimit(2)
            Spacer()
            Button("Cancel", action: onCancel).keyboardShortcut(.cancelAction)
            Button(confirmLabel, role: destructive ? .destructive : nil, action: onConfirm)
                .keyboardShortcut(.defaultAction)
        }
        .controlSize(.small)
    }
}
#endif
