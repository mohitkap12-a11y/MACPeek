#if os(macOS)
import AppKit
import SwiftUI
import ServiceManagement
import VitalsKit

enum AppearanceMode: String, CaseIterable, Identifiable {
    case system, light, dark
    var id: String { rawValue }
    var label: String { rawValue.capitalized }
    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
    var nsAppearance: NSAppearance? {
        switch self {
        case .system: return nil
        case .light: return NSAppearance(named: .aqua)
        case .dark: return NSAppearance(named: .darkAqua)
        }
    }
}

/// Minimal v1 settings, persisted in UserDefaults. Nothing is ever transmitted.
@MainActor
final class AppSettings: ObservableObject {
    static let refreshChoices: [Double] = [1, 2, 5, 10]

    @Published var refreshInterval: Double { didSet { defaults.set(refreshInterval, forKey: "refreshInterval") } }
    @Published var confirmBeforeKill: Bool { didSet { defaults.set(confirmBeforeKill, forKey: "confirmBeforeKill") } }
    @Published var showNotifications: Bool { didSet { defaults.set(showNotifications, forKey: "showNotifications") } }
    @Published var appearance: AppearanceMode {
        didSet {
            defaults.set(appearance.rawValue, forKey: "appearance")
            NSApp.appearance = appearance.nsAppearance
        }
    }
    /// Alerts (runaway processes, memory growth, pressure, swap, network, heat). On by default; each one can be turned off.
    @Published var alertsEnabled: Bool { didSet { defaults.set(alertsEnabled, forKey: "alerts.enabled") } }
    @Published var alertSettings: AlertSettings {
        didSet { defaults.set(try? JSONEncoder().encode(alertSettings), forKey: "alerts.settings") }
    }
    /// The 24-hour history of CPU, memory, network, GPU and temperature, kept on this Mac.
    @Published var historyEnabled: Bool { didSet { defaults.set(historyEnabled, forKey: "history.enabled") } }
    /// What the menu-bar readout shows next to the icon. Empty (the default) shows the icon only.
    @Published var menuBarMetrics: [MenuBarMetric] {
        didSet { defaults.set(menuBarMetrics.map(\.rawValue), forKey: "menuBar.metrics") }
    }
    /// With a readout, whether MacPeek's magnifier icon stays in front of it.
    @Published var menuBarShowsIcon: Bool { didSet { defaults.set(menuBarShowsIcon, forKey: "menuBar.showsIcon") } }
    /// Process lists group an app's helper processes (browser tabs, Electron helpers) under the app.
    @Published var groupAppHelpers: Bool { didSet { defaults.set(groupAppHelpers, forKey: "groupAppHelpers") } }
    @Published private(set) var launchAtLogin: Bool
    @Published var launchAtLoginError: String?

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let interval = defaults.double(forKey: "refreshInterval")
        refreshInterval = interval > 0 ? interval : 2
        confirmBeforeKill = defaults.object(forKey: "confirmBeforeKill") as? Bool ?? true
        showNotifications = defaults.object(forKey: "showNotifications") as? Bool ?? true
        appearance = AppearanceMode(rawValue: defaults.string(forKey: "appearance") ?? "") ?? .system
        alertsEnabled = defaults.object(forKey: "alerts.enabled") as? Bool ?? true
        alertSettings = defaults.data(forKey: "alerts.settings").flatMap { try? JSONDecoder().decode(AlertSettings.self, from: $0) } ?? .default
        historyEnabled = defaults.object(forKey: "history.enabled") as? Bool ?? true
        menuBarMetrics = (defaults.stringArray(forKey: "menuBar.metrics") ?? []).compactMap(MenuBarMetric.init(rawValue:))
        menuBarShowsIcon = defaults.object(forKey: "menuBar.showsIcon") as? Bool ?? true
        groupAppHelpers = defaults.object(forKey: "groupAppHelpers") as? Bool ?? true
        launchAtLogin = SMAppService.mainApp.status == .enabled
        NSApp.appearance = appearance.nsAppearance
    }

    /// Never alert about this app again (from an alert's "Don't alert about this app").
    func ignoreInAlerts(_ processName: String) {
        guard !alertSettings.ignores(processName) else { return }
        alertSettings.ignoredProcesses.append(processName)
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            launchAtLoginError = nil
        } catch {
            launchAtLoginError = "Could not change login item (run the installed app from /Applications)."
        }
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }
}
#endif
