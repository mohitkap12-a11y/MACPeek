#if os(macOS)
import AppKit
import SwiftUI
import ServiceManagement

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
        launchAtLogin = SMAppService.mainApp.status == .enabled
        NSApp.appearance = appearance.nsAppearance
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
