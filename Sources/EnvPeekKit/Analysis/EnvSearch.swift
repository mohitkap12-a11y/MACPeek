import Foundation

public enum EnvSearch {
    /// Every whitespace-separated word must appear in the name or the value (case-insensitive). Sorted by name.
    ///
    /// The value of a credential-looking variable is only searched once the user has revealed it (`revealedIDs`),
    /// so typing guesses into the search box cannot be used to learn what a hidden value contains.
    public static func filter(_ variables: [EnvVariable], query: String, revealedIDs: Set<String> = []) -> [EnvVariable] {
        let words = query.lowercased().split(whereSeparator: \.isWhitespace).map(String.init)
        let matched = variables.filter { variable in
            guard !words.isEmpty else { return true }
            let searchable = !variable.isSensitive || revealedIDs.contains(variable.id)
            let haystack = (searchable ? variable.name + " " + variable.value : variable.name).lowercased()
            return words.allSatisfy { haystack.contains($0) }
        }
        return matched.sorted { ($0.name.lowercased(), $0.occurrence) < ($1.name.lowercased(), $1.occurrence) }
    }
}
