import Foundation

/// Finds URLs, numbers, and backtick spans that were removed or added by a rewrite.
enum Protected {
    private static let regexes = [
        #"https?://[^\s<>"')\]]+"#,
        #"\d+(?:[.,:/\-]\d+)*"#,
        #"`[^`\n]+`"#,
    ].map { try! NSRegularExpression(pattern: $0) }

    static func tokens(in text: String) -> Set<String> {
        var found = Set<String>()
        for re in regexes {
            for m in re.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
                guard let r = Range(m.range, in: text) else { continue }
                found.insert(String(text[r]).trimmingCharacters(in: CharacterSet(charactersIn: ".,;:!?")))
            }
        }
        return found
    }

    static func flags(original: String, revised: String) -> [String] {
        let before = tokens(in: original)
        let after = tokens(in: revised)
        var flags: [String] = []
        let removed = before.subtracting(after).sorted()
        let added = after.subtracting(before).sorted()
        if !removed.isEmpty { flags.append("Missing from revision: " + removed.joined(separator: ", ")) }
        if !added.isEmpty { flags.append("Added in revision: " + added.joined(separator: ", ")) }
        return flags
    }
}
