import Foundation

struct TopicSegment: Codable {
    let title: String
    let startTime: Double
    let endTime: Double
    let summary: String
    let formattedTranscript: String
}

final class BedrockTopicSegmenter {
    private let bedrock: BedrockService

    init(bedrock: BedrockService) {
        self.bedrock = bedrock
    }

    func segmentTopics(transcript: String, profile: String) async throws -> [TopicSegment] {
        let prompt = """
You are given a transcript made of lines in the format:
start_epoch|end_epoch|text

Your task:
- Split the transcript into semantic topics.
- Return JSON only, with this schema:
{
  "topics": [
    {
      "title": "short title",
      "startTime": 1700000000.00,
      "endTime": 1700001234.56,
      "summary": "short summary",
      "formattedTranscript": "cleaned transcript for this topic"
    }
  ]
}

Rules:
- Use startTime/endTime values from the transcript lines; do not invent times.
- Topics should be contiguous and cover the transcript in order.
- Keep titles short.
- Prefer topic segments to be at least 10 minutes long. Only create shorter topics if necessary (e.g., transcript is short or there is a clear semantic boundary).
- Output JSON only, no extra text, no code fences.
- Summaries and titles must be in Japanese.
- formattedTranscript must be in Japanese and easy to read (remove filler, normalize punctuation, add line breaks).

Transcript:
\(transcript)
"""

        let response = try await bedrock.invokeRaw(prompt: prompt, profile: profile)
        if !response.isEmpty {
            AppLog.shared.add("Bedrock response (full): \(response)")
        }
        guard let json = extractJSON(from: response) else {
            AppLog.shared.add("Bedrock response missing JSON")
            throw NSError(domain: "BedrockTopicSegmenter", code: 1, userInfo: [NSLocalizedDescriptionKey: "JSON not found"])
        }
        guard let topics = parseTopics(json: json), !topics.isEmpty else {
            AppLog.shared.add("Bedrock response JSON parse failed")
            throw NSError(domain: "BedrockTopicSegmenter", code: 2, userInfo: [NSLocalizedDescriptionKey: "JSON parse failed"])
        }
        return topics
    }

    private struct TopicResponse: Codable {
        let topics: [TopicSegment]
    }

    private func extractJSON(from text: String) -> String? {
        if let fenceStart = text.range(of: "```"), let fenceEnd = text.range(of: "```", range: fenceStart.upperBound..<text.endIndex) {
            var inside = text[fenceStart.upperBound..<fenceEnd.lowerBound]
            inside = inside.trimmingCharacters(in: .whitespacesAndNewlines)[...]
            if inside.hasPrefix("json") {
                inside = inside.dropFirst(4)
            }
            let trimmed = inside.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.first == "{" && trimmed.last == "}" { return String(trimmed) }
        }
        guard let start = text.firstIndex(of: "{"), let end = text.lastIndex(of: "}") else { return nil }
        return String(text[start...end])
    }

    private func parseTopics(json: String) -> [TopicSegment]? {
        guard let data = json.data(using: .utf8) else { return nil }
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        guard let rawTopics = obj["topics"] as? [[String: Any]] else { return nil }

        var topics: [TopicSegment] = []
        for item in rawTopics {
            let title = item["title"] as? String ?? "無題"
            let summary = item["summary"] as? String ?? ""
            let formatted = item["formattedTranscript"] as? String ?? ""
            let startTime = parseDouble(item["startTime"]) ?? 0
            let endTime = parseDouble(item["endTime"]) ?? 0
            if startTime <= 0 || endTime <= 0 { continue }
            topics.append(TopicSegment(title: title, startTime: startTime, endTime: endTime, summary: summary, formattedTranscript: formatted))
        }
        return topics
    }

    private func parseDouble(_ value: Any?) -> Double? {
        if let num = value as? NSNumber { return num.doubleValue }
        if let str = value as? String { return Double(str) }
        return nil
    }
}
