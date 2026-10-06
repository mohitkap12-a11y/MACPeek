#if os(macOS)
import SwiftUI
import AppKit
import PortPeekCore

struct PortRowView: View {
    @EnvironmentObject private var store: PortStore
    let port: PortInfo

    private var expanded: Bool { store.selectedID == port.id }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Text(String(port.port))
                    .font(.system(size: 14, weight: .semibold, design: .monospaced))
                    .frame(width: 58, alignment: .leading)
                VStack(alignment: .leading, spacing: 1) {
                    Text(port.processName).font(.system(size: 13)).lineLimit(1)
                    Text("PID \(port.pid)").font(.caption).foregroundStyle(.secondary)
                }
                Spacer(minLength: 4)
                Text(port.protocolType.rawValue)
                    .font(.system(size: 10, weight: .medium))
                    .padding(.horizontal, 5).padding(.vertical, 2)
                    .background(.quaternary, in: RoundedRectangle(cornerRadius: 4))
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.tertiary)
                    .rotationEffect(.degrees(expanded ? 90 : 0))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
            .onTapGesture { withAnimation(.easeOut(duration: 0.15)) { store.selectedID = expanded ? nil : port.id } }

            if expanded {
                PortDetailView(port: port)
                    .transition(.opacity)
            }
        }
        .background(expanded ? Color.accentColor.opacity(0.08) : .clear)
        .id(port.id)
        .contextMenu {
            Button("Copy Port") { copy(String(port.port)) }
            Button("Copy PID") { copy(String(port.pid)) }
            Button("Copy Address") { copy(port.endpoint) }
            if port.protocolType == .tcp {
                Button("Open http://localhost:\(port.port)") {
                    if let url = URL(string: "http://localhost:\(port.port)") { NSWorkspace.shared.open(url) }
                }
            }
            Divider()
            Button("Terminate…") { store.selectedID = port.id }
        }
    }

    private func copy(_ string: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(string, forType: .string)
    }
}
#endif
