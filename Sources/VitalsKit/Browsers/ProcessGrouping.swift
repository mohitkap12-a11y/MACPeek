import Foundation

/// The app a helper process belongs to. Browsers and Electron apps run each tab, extension and GPU job in a helper
/// process ("Google Chrome Helper (Renderer)", "Code Helper (GPU)"), so a list of processes shows one browser as twenty
/// rows. Grouping puts them back under the app, with a hint where the app can say which tab is busy.
public struct AppFamily: Hashable, Codable, Sendable {
    /// What the group is called: "Google Chrome", "Safari and web views", "Code".
    public let name: String
    /// Where the app itself shows per-tab use, when it can ("Window ▸ Task Manager"). Nil for apps without one.
    public let tabHint: String?
    public let isBrowser: Bool

    public init(name: String, tabHint: String?, isBrowser: Bool) {
        self.name = name
        self.tabHint = tabHint
        self.isBrowser = isBrowser
    }
}

public enum ProcessGrouping {
    private struct Browser {
        let family: AppFamily
        /// Process names (as macOS reports them, at most 32 characters) that belong to it, matched as prefixes.
        let prefixes: [String]
        /// Names matched exactly.
        let exact: [String]
    }

    private static let chromiumHint = "Its Task Manager (Window ▸ Task Manager, or Shift-Esc) shows which tab is busy."

    private static let browsers: [Browser] = [
        Browser(family: AppFamily(name: "Google Chrome", tabHint: chromiumHint, isBrowser: true),
                prefixes: ["Google Chrome"], exact: []),
        Browser(family: AppFamily(name: "Brave", tabHint: chromiumHint, isBrowser: true),
                prefixes: ["Brave Browser"], exact: []),
        Browser(family: AppFamily(name: "Microsoft Edge", tabHint: "Its Browser Task Manager (Shift-Esc) shows which tab is busy.", isBrowser: true),
                prefixes: ["Microsoft Edge"], exact: []),
        Browser(family: AppFamily(name: "Chromium", tabHint: chromiumHint, isBrowser: true),
                prefixes: ["Chromium"], exact: []),
        Browser(family: AppFamily(name: "Vivaldi", tabHint: "Its Task Manager (Shift-Esc) shows which tab is busy.", isBrowser: true),
                prefixes: ["Vivaldi"], exact: []),
        Browser(family: AppFamily(name: "Opera", tabHint: "Its Task Manager (Shift-Esc) shows which tab is busy.", isBrowser: true),
                prefixes: ["Opera"], exact: []),
        Browser(family: AppFamily(name: "Arc", tabHint: nil, isBrowser: true),
                prefixes: ["Arc Helper"], exact: ["Arc"]),
        Browser(family: AppFamily(name: "Firefox", tabHint: "Type about:processes in the address bar to see which tab is busy.", isBrowser: true),
                prefixes: ["firefox", "Firefox"], exact: ["plugin-container"]),
        // WebKit's helpers serve Safari and every app that shows web pages (Mail, App Store, apps with web views).
        Browser(family: AppFamily(name: "Safari and web views",
                                  tabHint: "Activity Monitor names Safari's tabs; MacPeek cannot see which page a helper shows.",
                                  isBrowser: true),
                prefixes: ["com.apple.WebKit.", "com.apple.Safari"], exact: ["Safari", "Safari Networking", "SafariBookmarksSyncAgent"]),
    ]

    /// The app a process belongs to: a known browser, or "<App>" for a process named "<App> Helper…" (Electron and
    /// Chromium-based apps such as Slack, VS Code or Discord). Nil for an ordinary process.
    public static func family(of processName: String) -> AppFamily? {
        let name = processName.trimmingCharacters(in: .whitespaces)
        for browser in browsers {
            if browser.exact.contains(name) || browser.prefixes.contains(where: { name.hasPrefix($0) }) {
                return browser.family
            }
        }
        if let range = name.range(of: " Helper") {
            let app = String(name[..<range.lowerBound]).trimmingCharacters(in: .whitespaces)
            let rest = name[range.upperBound...]
            // "Slack Helper", "Slack Helper (Renderer)", "Code Helper (GPU)"; not "HelperTool" or "Help Viewer".
            guard !app.isEmpty, rest.isEmpty || rest.hasPrefix(" (") else { return nil }
            return AppFamily(name: app, tabHint: nil, isBrowser: false)
        }
        return nil
    }

    /// One app's processes, or one ordinary process on its own.
    public struct Group<Item: Sendable>: Sendable {
        /// Nil for an ordinary process (a group of one).
        public let family: AppFamily?
        public let items: [Item]
        /// The sum of `value` over the items.
        public let total: Double

        public var title: String { family?.name ?? "" }
    }

    /// Groups rows by app family. A family is grouped only when it has at least two processes (an app's main process
    /// counts when its name is the family name); everything else stays a group of one. Groups are ordered by `total`,
    /// largest first, and keep the items' order inside.
    public static func group<Item: Sendable>(_ items: [Item], name: (Item) -> String, value: (Item) -> Double) -> [Group<Item>] {
        var families: [AppFamily] = []
        var members: [AppFamily: [Item]] = [:]
        var singles: [Item] = []
        // An app's own process ("Slack", "Code") joins its helpers' family when one exists.
        let helperFamilies = Set(items.compactMap { Self.family(of: name($0)) }.map(\.name))
        for item in items {
            let itemName = name(item)
            var match = Self.family(of: itemName)
            if match == nil, helperFamilies.contains(itemName) {
                match = AppFamily(name: itemName, tabHint: nil, isBrowser: false)
            }
            guard let family = match else {
                singles.append(item)
                continue
            }
            // A main process's family must match its helpers' (same name, same hint).
            let resolved = families.first { $0.name == family.name } ?? family
            if members[resolved] == nil { families.append(resolved) }
            members[resolved, default: []].append(item)
        }
        var groups: [Group<Item>] = []
        for family in families {
            let items = members[family] ?? []
            if items.count >= 2 {
                groups.append(Group(family: family, items: items, total: items.reduce(0) { $0 + value($1) }))
            } else {
                singles.append(contentsOf: items)
            }
        }
        groups += singles.map { Group(family: nil, items: [$0], total: value($0)) }
        return groups.enumerated().sorted { a, b in
            a.element.total != b.element.total ? a.element.total > b.element.total : a.offset < b.offset
        }.map(\.element)
    }
}
