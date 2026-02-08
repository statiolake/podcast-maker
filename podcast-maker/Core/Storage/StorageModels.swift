struct SegmentRecord: Codable {
    let id: String
    let startTime: Double
    let endTime: Double
    let duration: Double
    let audioPath: String
    let text: String
    let status: String
}

struct TranscriptRecord: Codable {
    let id: String
    let startTime: Double
    let segments: [TranscriptSegment]
}

struct TranscriptSegment: Codable {
    let startTime: Double
    let endTime: Double
    let text: String
}
