import Foundation

enum SnippetGuard {
    static func blockingWarnings(for mappings: [Mapping]) -> [String] {
        mappings.compactMap { mapping in
            guard mapping.enabled, looksSensitive(mapping.text) else { return nil }
            let label = mapping.name.isEmpty ? mapping.combo.description : mapping.name
            return "Blocked save: \(label) looks like password/token/private key material. KyB refuses secret-like snippets."
        }
    }

    private static func looksSensitive(_ text: String) -> Bool {
        let lower = text.lowercased()
        let sensitiveWords = [
            "password", "passwd", "token", "secret", "api_key", "apikey", "private key",
            "bearer ", "authorization:", "aws_access_key", "aws_secret", "BEGIN PRIVATE KEY".lowercased(),
        ]
        if sensitiveWords.contains(where: { lower.contains($0) }) { return true }

        let compact = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if compact.count >= 24, compact.range(of: #"^[A-Za-z0-9_+\-/=.]{24,}$"#, options: .regularExpression) != nil {
            return true
        }
        if compact.range(of: #"(?i)sk-[A-Za-z0-9]{20,}"#, options: .regularExpression) != nil { return true }
        if compact.range(of: #"(?i)xox[baprs]-[A-Za-z0-9-]{20,}"#, options: .regularExpression) != nil { return true }
        if compact.range(of: #"AKIA[0-9A-Z]{16}"#, options: .regularExpression) != nil { return true }
        return false
    }
}
