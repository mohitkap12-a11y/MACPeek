import Foundation

public enum EnvSearch {
    /// Every whitespace-separated word must appear in the name or the value (case-insensitive). Sorted by name.
    public static func filter(_ variables: [EnvVariable], query: String) -> [EnvVariable] {
        let words = query.lowercased().split(whereSeparator: \.isWhitespace).map(String.init)
        let matched = variables.filter { variable in
            guard !words.isEmpty else { return true }
            let haystack = (variable.name + " " + variable.value).lowercased()
            return words.allSatisfy { haystack.contains($0) }
        }
        return matched.sorted { $0.name.lowercased() < $1.name.lowercased() }
    }
}
