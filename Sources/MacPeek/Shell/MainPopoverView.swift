#if os(macOS)
import SwiftUI

/// The popover content: a router over the launcher, utility screens, manager, settings and about.
struct MainPopoverView: View {
    @EnvironmentObject private var router: UtilityRouter
    @EnvironmentObject private var settings: AppSettings

    var body: some View {
        Group {
            switch router.route {
            case .launcher: LauncherView()
            case .utility(let id): UtilityContainerView(id: id)
            case .manage: UtilityManagerView()
            case .settings: SettingsView()
            case .about: AboutView()
            }
        }
        .frame(width: 380, height: 520)
        .background(.background)
        .preferredColorScheme(settings.appearance.colorScheme)
        .animation(.easeOut(duration: 0.12), value: router.route)
    }
}
#endif
