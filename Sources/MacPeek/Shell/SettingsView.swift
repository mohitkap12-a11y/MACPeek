#if os(macOS)
import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var router: UtilityRouter

    var body: some View {
        VStack(spacing: 0) {
            PeekHeader(title: "Settings", onBack: { router.back() })
            Divider()
            Form {
                Section("Utilities") {
                    Button("Manage utilities…") { router.go(.manage) }
                }
                Section("General") {
                    Toggle("Launch at login", isOn: Binding(get: { settings.launchAtLogin }, set: settings.setLaunchAtLogin))
                    if let error = settings.launchAtLoginError {
                        Text(error).font(.caption).foregroundStyle(.orange)
                    }
                    Picker("Refresh every", selection: $settings.refreshInterval) {
                        ForEach(AppSettings.refreshChoices, id: \.self) { Text("\(Int($0)) s").tag($0) }
                    }
                    Text("Applies to utilities that refresh live. Refreshing happens only while a utility is on screen.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Section("Behavior") {
                    Toggle("Confirm before kill", isOn: $settings.confirmBeforeKill)
                    Toggle("Show notification after kill", isOn: $settings.showNotifications)
                    Text("MacPeek always asks a process to quit gracefully first. Force kill is a separate, explicit step.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Section("Appearance") {
                    Picker("Theme", selection: $settings.appearance) {
                        ForEach(AppearanceMode.allCases) { Text($0.label).tag($0) }
                    }
                    .pickerStyle(.segmented)
                }
                Section("Privacy") {
                    Text("No account, no telemetry, no network access. Data from your Mac never leaves it.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)
        }
    }
}
#endif
