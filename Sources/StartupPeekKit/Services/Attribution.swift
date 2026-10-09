import Foundation

/// Path-based attribution. These are inferences from where a file lives, so callers word them as "likely".
public enum Attribution {
    /// The `.app` bundle containing `path`, e.g. "/Applications/Example.app/Contents/MacOS/helper" → "/Applications/Example.app".
    public static func enclosingAppBundle(of path: String) -> String? {
        let components = path.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
        guard let index = components.firstIndex(where: { $0.hasSuffix(".app") && $0.count > 4 }) else { return nil }
        return "/" + components[0...index].joined(separator: "/")
    }

    /// "Example" for "/Applications/Example.app/…".
    public static func appName(from path: String) -> String? {
        guard let bundle = enclosingAppBundle(of: path) else { return nil }
        let last = (bundle as NSString).lastPathComponent
        return String(last.dropLast(4))
    }

    /// Falls back to the last component of a reverse-DNS bundle identifier ("com.example.Helper" → "Helper").
    public static func appName(fromBundleIdentifier identifier: String) -> String? {
        let last = identifier.split(separator: ".").last.map(String.init)
        return last?.isEmpty == false ? last : nil
    }

    private static let commonRoots = ["/Applications/", "/System/", "/usr/", "/bin/", "/sbin/", "/Library/", "/opt/homebrew/",
                                      "/opt/", "/private/var/db/"]

    /// True when `path` is somewhere programs normally live. `home` is injected for tests.
    public static func isInCommonLocation(_ path: String, home: String = NSHomeDirectory()) -> Bool {
        if commonRoots.contains(where: { path.hasPrefix($0) }) { return true }
        let homeApps = home.hasSuffix("/") ? home : home + "/"
        return path.hasPrefix(homeApps + "Applications/") || path.hasPrefix(homeApps + "Library/")
    }

    /// The neutral observations StartupPeek may show. Never "suspicious", "unsafe" or "malware".
    public static func observations(executablePath: String?, signature: SignatureInfo, executableExists: Bool?,
                                    home: String = NSHomeDirectory()) -> [String] {
        var notes: [String] = []
        guard let executablePath else {
            return ["The property list does not name an executable"]
        }
        if executableExists == false { notes.append("The executable was not found at the listed path") }
        if !isInCommonLocation(executablePath, home: home) { notes.append("Path is outside common application locations") }
        if signature == .unsigned || signature == .unavailable, executableExists != false {
            notes.append("Attribution could not be verified")
        }
        return notes
    }
}
