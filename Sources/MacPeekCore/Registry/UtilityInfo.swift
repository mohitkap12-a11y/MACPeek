import Foundation

public enum UtilityCategory: String, Sendable, CaseIterable {
    case everyday = "Utilities"
    case developer = "Developer"
}

public enum UtilityAvailability: String, Sendable {
    case available
    case comingSoon
}

/// Metadata the shell needs about a utility: enough to list it, explain it and toggle it —
/// never how it gathers data. Utilities own their models, services and views.
public struct UtilityInfo: Identifiable, Hashable, Sendable {
    public let id: String
    public let name: String
    /// The user question it answers, e.g. "What is using port 3000?"
    public let question: String
    /// One line shown in the launcher when no live summary is available.
    public let tagline: String
    /// A short paragraph for the "learn more" panel.
    public let summary: String
    /// SF Symbol name.
    public let icon: String
    public let category: UtilityCategory
    public let availability: UtilityAvailability
    /// What it reads from the Mac (honest, specific).
    public let reads: [String]
    /// What access it needs (or doesn't).
    public let permissions: [String]

    public init(
        id: String, name: String, question: String, tagline: String, summary: String, icon: String,
        category: UtilityCategory, availability: UtilityAvailability, reads: [String], permissions: [String]
    ) {
        self.id = id
        self.name = name
        self.question = question
        self.tagline = tagline
        self.summary = summary
        self.icon = icon
        self.category = category
        self.availability = availability
        self.reads = reads
        self.permissions = permissions
    }

    public var isAvailable: Bool { availability == .available }
}
