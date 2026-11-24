#if os(macOS)
import SwiftUI
import VitalsKit

/// Recent alerts, newest first: what happened, when, and where to look. Process alerts offer "Don't alert about this
/// app". Alerts are raised by `VitalsMonitor` and kept across launches (the last 50).
struct AlertsView: View {
    @EnvironmentObject private var router: UtilityRouter
    @EnvironmentObject private var monitor: VitalsMonitor
    @EnvironmentObject private var settings: AppSettings

    var body: some View {
        VStack(spacing: 0) {
            PeekHeader(title: "Alerts", subtitle: settings.alertsEnabled ? "On" : "Off", onBack: { router.back() }) {
                if !monitor.recentAlerts.isEmpty {
                    Button("Clear") { monitor.clearAlerts() }.buttonStyle(.borderless).font(.caption)
                }
            }
            Divider()
            if !settings.alertsEnabled {
                EmptyState(symbol: "bell.slash", title: "Alerts are off",
                           message: "Turn them on to hear about stuck processes, memory leaks, heavy swapping, busy networks and heat.",
                           actionTitle: "Turn on alerts", action: { settings.alertsEnabled = true })
            } else if monitor.recentAlerts.isEmpty {
                EmptyState(symbol: "checkmark.circle", title: "Nothing to report",
                           message: "MacPeek watches for processes stuck at high CPU, memory that keeps growing, memory pressure, swap, sustained network traffic and heat, and tells you here and in Notification Center.",
                           actionTitle: "Alert settings", action: { router.go(.settings) })
            } else {
                ScrollView {
                    VStack(spacing: 8) {
                        ForEach(monitor.recentAlerts) { alert in AlertRow(alert: alert) }
                    }
                    .padding(14)
                }
            }
            Divider()
            HStack {
                Button("Alert settings…") { router.go(.settings) }
                Spacer()
                Text("Checked on this Mac only").foregroundStyle(PeekTheme.muted)
            }
            .buttonStyle(.borderless)
            .font(.caption)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
        }
        .background(PeekTheme.ground)
        .onAppear { monitor.markAlertsSeen() }
    }
}

private struct AlertRow: View {
    @EnvironmentObject private var router: UtilityRouter
    @EnvironmentObject private var settings: AppSettings
    let alert: AlertEvent

    private var color: Color { alert.isCritical ? PeekTheme.red : PeekTheme.amber }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: alert.kind.symbol)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(color)
                    .frame(width: 22)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 3) {
                    Text(alert.title).font(.system(size: 13, weight: .semibold)).fixedSize(horizontal: false, vertical: true)
                    Text(alert.message).font(.system(size: 12)).foregroundStyle(PeekTheme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("\(alert.time, style: .relative) ago").font(.system(size: 10.5)).foregroundStyle(PeekTheme.muted)
                }
                Spacer(minLength: 0)
            }
            HStack(spacing: 12) {
                Button("Open \(utilityName)") { router.go(.utility(alert.kind.utilityID)) }
                if let name = alert.processName {
                    Button(settings.alertSettings.ignores(name) ? "Ignored" : "Don't alert about \(name)") {
                        settings.ignoreInAlerts(name)
                    }
                    .disabled(settings.alertSettings.ignores(name))
                }
            }
            .buttonStyle(.borderless)
            .font(.caption)
            .padding(.leading, 32)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .themedCard(radius: 10, padding: 10)
        .accessibilityElement(children: .contain)
    }

    private var utilityName: String {
        switch alert.kind.utilityID {
        case "cpupeek": return "CPUPeek"
        case "memorypeek": return "MemoryPeek"
        case "netpeek": return "NetPeek"
        default: return "MacPeek"
        }
    }
}
#endif
