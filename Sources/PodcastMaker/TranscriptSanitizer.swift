import Foundation

struct TranscriptSanitizer {
    static func isBlank(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return true }
        if trimmed == "[BLANK_AUDIO]" { return true }
        if isThanksOnly(trimmed) { return true }
        if isParenthesesOnly(trimmed) { return true }
        return false
    }

    static func sanitizeForBedrock(_ text: String) -> String {
        let lines = text.components(separatedBy: .newlines)
        let sanitized = lines.map { line -> String in
            let parts = line.split(separator: "|", omittingEmptySubsequences: false)
            if parts.count < 3 { return line }
            let start = parts[0]
            let end = parts[1]
            let body = parts[2...].joined(separator: "|")
            let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
            let replaced = isBlank(trimmed) ? "" : body
            return "\(start)|\(end)|\(replaced)"
        }
        return sanitized.joined(separator: "\n")
    }

    private static func isThanksOnly(_ text: String) -> Bool {
        let pattern = "^ご視聴ありがとうございました(?:[\"。！])?$"
        return text.range(of: pattern, options: [.regularExpression]) != nil
    }

    private static func isParenthesesOnly(_ text: String) -> Bool {
        let pattern = "^\\(.*\\)$"
        return text.range(of: pattern, options: [.regularExpression]) != nil
    }
}
