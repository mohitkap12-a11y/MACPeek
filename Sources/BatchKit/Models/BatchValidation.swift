import Foundation
import MacPeekCore

/// What a batch may contain. Everything that becomes part of a command line or a request is checked here first, so a
/// name can never be read as an option or reach another program.
public enum BatchValidation {
    public static let maximumItems = 20
    public static let maximumNameLength = 100

    private static let planID = NSRegularExpression.compile(#"^[A-Za-z0-9-]{1,64}$"#)
    /// Homebrew names: letters, digits and `@ . _ + - /` (taps: `owner/tap/name`); never starting with `-`.
    private static let brewName = NSRegularExpression.compile(#"^[A-Za-z0-9][A-Za-z0-9@._+/-]{0,199}$"#)
    /// Ollama models: `llama3.3:70b`, `library/qwen3`, `hf.co/owner/Repo-GGUF:Q4_K_M`; never starting with `-`.
    private static let ollamaName = NSRegularExpression.compile(#"^[A-Za-z0-9][A-Za-z0-9._/-]{0,254}(:[A-Za-z0-9._-]{1,128})?$"#)
    /// Image references: `postgres:17`, `ghcr.io/team/app:1.2`, `app@sha256:…`; never starting with `-`.
    private static let imageReference = NSRegularExpression.compile(#"^[A-Za-z0-9][A-Za-z0-9._/:@-]{0,254}$"#)

    /// The reason the item cannot be installed as written, or nil when it is fine.
    public static func problem(with item: BatchItem) -> String? {
        let name = item.name
        guard !name.contains("..") else { return "“\(name)” is not a valid name." }
        switch item.kind {
        case .brewFormula, .brewCask:
            guard brewName.groups(in: name) != nil else { return "“\(name)” is not a Homebrew package name." }
        case .ollamaModel:
            guard ollamaName.groups(in: name) != nil else { return "“\(name)” is not an Ollama model name." }
        case .containerImage:
            guard imageReference.groups(in: name) != nil else { return "“\(name)” is not an image reference." }
        }
        if item.startService, item.kind != .brewFormula { return "Only a Homebrew formula can be started as a service." }
        return nil
    }

    /// The reason the plan cannot run, or nil when it is fine.
    public static func problem(with plan: BatchPlan) -> String? {
        guard planID.groups(in: plan.id) != nil else { return "The batch has no valid id." }
        let name = plan.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, plan.name.count <= maximumNameLength, !plan.name.contains(where: \.isNewline) else {
            return "A batch needs a name of at most \(maximumNameLength) characters on one line."
        }
        guard !plan.items.isEmpty else { return "The batch has nothing to install." }
        guard plan.items.count <= maximumItems else { return "A batch installs at most \(maximumItems) things." }
        var seen = Set<String>()
        for item in plan.items {
            if let problem = problem(with: item) { return problem }
            guard seen.insert("\(item.kind.rawValue) \(item.name)").inserted else { return "\(item.title) is listed twice." }
        }
        return nil
    }
}
