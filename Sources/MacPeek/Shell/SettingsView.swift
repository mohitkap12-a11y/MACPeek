#if os(macOS)
import SwiftUI
import MacPeekCore
import VitalsKit

struct SettingsView: View {
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var router: UtilityRouter
    @EnvironmentObject private var updater: UpdaterService
    @EnvironmentObject private var remote: RemoteManagementController
    @EnvironmentObject private var monitor: VitalsMonitor

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
                AlertSettingsSection()
                Section("Menu bar") {
                    ForEach(MenuBarMetric.allCases) { metric in
                        Toggle(metric.title, isOn: Binding(
                            get: { settings.menuBarMetrics.contains(metric) },
                            set: { on in
                                var metrics = settings.menuBarMetrics.filter { $0 != metric }
                                if on { metrics.append(metric) }
                                // Keep a fixed order, whatever order they were switched on in.
                                settings.menuBarMetrics = MenuBarMetric.allCases.filter { metrics.contains($0) }
                            }))
                    }
                    if !settings.menuBarMetrics.isEmpty {
                        Toggle("Show MacPeek's icon too", isOn: $settings.menuBarShowsIcon)
                    }
                    Text(settings.menuBarMetrics.isEmpty
                         ? "Show live readings next to MacPeek's icon. Off by default."
                         : "Updates every \(Int(min(settings.refreshInterval, VitalsMonitor.tickSeconds))) s. If the readings disappear, macOS hid them because the menu bar is full.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Section("History") {
                    Toggle("Keep 24 hours of history", isOn: $settings.historyEnabled)
                    if settings.historyEnabled {
                        Button("View history…") { router.go(.history) }
                        Button("Delete history", role: .destructive) { monitor.clearHistory() }
                    }
                    Text("CPU, memory, network, GPU, temperature and power, averaged every 10 seconds and kept on this Mac for a day. Turning it off deletes it.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Section("Behavior") {
                    Toggle("Group app helper processes", isOn: $settings.groupAppHelpers)
                        .help("Browsers and Electron apps run every tab and window in helper processes. Grouping lists them under their app.")
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
                Section("Updates") {
                    if updater.isAvailable {
                        Toggle("Check for updates automatically", isOn: $updater.automaticallyChecks)
                        Button("Check for Updates…") { updater.checkForUpdates() }
                            .disabled(!updater.canCheckForUpdates)
                        if updater.receivesPreviewBuilds {
                            LabeledContent("Preview builds") {
                                Button("Back to stable") { updater.stopPreviewBuilds() }
                                    .help("Stop receiving previews. The installed preview stays until a newer stable release.")
                            }
                            Text("This Mac receives preview releases before everyone else.")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Text("About once a day MacPeek asks GitHub whether a newer release exists. Nothing about you or your Mac is sent beyond what any web request includes. Updates are verified with a signature before they are installed.")
                            .font(.caption).foregroundStyle(.secondary)
                    } else {
                        Text("Updates are available in the downloaded release. This build was not packaged with an update key.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                Section("Remote management") {
                    Button {
                        router.go(.remote)
                    } label: {
                        LabeledContent("MacPeek Remote", value: remote.isEnabled ? "On" : "Off")
                    }
                    .buttonStyle(.plain)
                    Text("Off by default. Lets MacPeek Remote, the console app for all your Macs, see this Mac from the devices of your account, and act on it if you allow.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Section("Privacy") {
                    Text("Alerts, the menu-bar readings and history are worked out on this Mac and never sent anywhere, except to devices of this Mac's MacPeek Remote account if you turn Remote management on.")
                        .font(.caption).foregroundStyle(.secondary)
                    Text("No account, no telemetry, nothing sent to MacPeek. The only network use is the update check above (which you can turn off), checks you start yourself (NetPeek, DNSPeek, UpdatePeek) and, only if you turn it on, Remote management, which talks to MacPeek Remote's service to add this Mac to your account and lets your account's devices connect on the local network or through the relay.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)
        }
    }
}

/// Alerts: on by default, each kind with its own switch and threshold.
private struct AlertSettingsSection: View {
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var router: UtilityRouter

    private static let gigabyte: UInt64 = 1 << 30

    var body: some View {
        Section("Alerts") {
            Toggle("Alert me when something looks wrong", isOn: $settings.alertsEnabled)
            if settings.alertsEnabled {
                Toggle("A process stays above \(Int(settings.alertSettings.runawayPercent))% CPU", isOn: $settings.alertSettings.runawayEnabled)
                if settings.alertSettings.runawayEnabled {
                    Picker("for", selection: $settings.alertSettings.runawayMinutes) {
                        ForEach([2, 5, 10, 30], id: \.self) { Text("\($0) min").tag($0) }
                    }
                }
                Toggle("A process's memory keeps growing", isOn: $settings.alertSettings.leakEnabled)
                if settings.alertSettings.leakEnabled {
                    Picker("by", selection: $settings.alertSettings.leakGrowthBytes) {
                        ForEach([1, 2, 4, 8].map { UInt64($0) * Self.gigabyte }, id: \.self) {
                            Text("\(ByteCountText.memory($0)) in \(settings.alertSettings.leakMinutes) min").tag($0)
                        }
                    }
                }
                Toggle("Memory pressure is high", isOn: $settings.alertSettings.pressureEnabled)
                Toggle("Swap grows quickly", isOn: $settings.alertSettings.swapEnabled)
                Toggle("Network stays busy", isOn: $settings.alertSettings.networkEnabled)
                if settings.alertSettings.networkEnabled {
                    Picker("above", selection: $settings.alertSettings.networkBytesPerSecond) {
                        ForEach([1_000_000.0, 5_000_000, 20_000_000, 100_000_000], id: \.self) {
                            Text("\(ByteCountText.binary($0))/s for \(settings.alertSettings.networkMinutes) min").tag($0)
                        }
                    }
                }
                Toggle("The Mac is running hot", isOn: $settings.alertSettings.thermalEnabled)
                if !settings.alertSettings.ignoredProcesses.isEmpty {
                    LabeledContent("Never alert about") {
                        Text(settings.alertSettings.ignoredProcesses.joined(separator: ", ")).lineLimit(2)
                    }
                    Button("Alert about every app again") { settings.alertSettings.ignoredProcesses = [] }
                }
                Button("Recent alerts…") { router.go(.alerts) }
            }
            Text("Alerts appear in Notification Center and under the bell in MacPeek. The same alert is not repeated within an hour. Checking costs a few cheap readings every 5 seconds and a process scan every 10.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
}
#endif
