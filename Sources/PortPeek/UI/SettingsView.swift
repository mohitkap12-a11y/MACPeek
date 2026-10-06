#if os(macOS)
import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var settings: AppSettings

    var body: some View {
        Form {
            Section("General") {
                Toggle("Launch at login", isOn: Binding(get: { settings.launchAtLogin }, set: settings.setLaunchAtLogin))
                if let error = settings.launchAtLoginError {
                    Text(error).font(.caption).foregroundStyle(.orange)
                }
                Picker("Refresh every", selection: $settings.refreshInterval) {
                    ForEach(AppSettings.refreshChoices, id: \.self) { Text("\(Int($0)) s").tag($0) }
                }
            }
            Section("Behavior") {
                Toggle("Confirm before kill", isOn: $settings.confirmBeforeKill)
                Toggle("Show notification after kill", isOn: $settings.showNotifications)
                Text("PortPeek always asks the process to quit gracefully first. Force kill is a separate, explicit step.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Appearance") {
                Picker("Theme", selection: $settings.appearance) {
                    ForEach(AppearanceMode.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
            }
            Section("Privacy") {
                Text("No account, no telemetry, no network access. Port and process data never leaves your Mac.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}
#endif
