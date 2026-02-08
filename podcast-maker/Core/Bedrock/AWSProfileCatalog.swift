import Foundation

struct AWSProfileCatalog {
    static var configPath: String {
        (FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".aws", isDirectory: true)
            .appendingPathComponent("config", isDirectory: false)).path
    }

    static func loadProfiles() -> [String] {
        let url = URL(fileURLWithPath: configPath)
        guard let text = try? String(contentsOf: url, encoding: .utf8) else {
            return ["default"]
        }
        return parseProfiles(from: text)
    }

    private static func parseProfiles(from text: String) -> [String] {
        let lines = text.components(separatedBy: .newlines)
        var ordered: [String] = []
        var seen = Set<String>()

        func append(_ value: String) {
            guard !value.isEmpty else { return }
            if seen.insert(value).inserted {
                ordered.append(value)
            }
        }

        for rawLine in lines {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard line.hasPrefix("[") && line.hasSuffix("]") else { continue }

            let section = String(line.dropFirst().dropLast()).trimmingCharacters(in: .whitespaces)
            if section == "default" {
                append("default")
                continue
            }
            if section.hasPrefix("profile ") {
                let profile = String(section.dropFirst("profile ".count))
                    .trimmingCharacters(in: .whitespaces)
                append(profile)
            }
        }

        if !seen.contains("default") {
            ordered.insert("default", at: 0)
        }
        return ordered
    }
}
