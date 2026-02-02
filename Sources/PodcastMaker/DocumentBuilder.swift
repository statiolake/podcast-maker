import Foundation

final class DocumentBuilder {
    private let aggregator = TranscriptAggregator()
    private let store = DocumentStore()
    private let merger = AudioMerger()
    private let bedrock: BedrockService

    init(bedrock: BedrockService) {
        self.bedrock = bedrock
    }

    func buildDocuments(hours: Double, profile: String, completion: @escaping (Bool) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            let segments = self.aggregator.loadRecentSegments(hours: hours)
            if segments.isEmpty {
                AppLog.shared.add("No transcripts in last \(Int(hours))h")
                DispatchQueue.main.async { completion(false) }
                return
            }

            let transcript = self.aggregator.combinedTranscriptText(segments: segments)
            AppLog.shared.add("Bedrock segmentation started (segments=\(segments.count))")

            Task {
                do {
                    let segmenter = BedrockTopicSegmenter(bedrock: self.bedrock)
                    let topics = try await segmenter.segmentTopics(transcript: transcript, profile: profile)
                    AppLog.shared.add("Bedrock segmentation done (topics=\(topics.count))")

                    for topic in topics {
                        let topicSegments = segments.filter { seg in
                            seg.endTime >= topic.startTime && seg.startTime <= topic.endTime
                        }
                        guard let audio = self.merger.merge(segments: topicSegments) else { continue }
                        let topicTranscript = topicSegments.map { $0.text }.joined(separator: " ")
                        let metadata = DocumentMetadata(
                            title: topic.title,
                            startTime: topic.startTime,
                            endTime: topic.endTime,
                            summary: topic.summary,
                            transcript: topicTranscript,
                            formattedTranscript: topic.formattedTranscript,
                            topics: topics,
                            createdAt: Date().timeIntervalSince1970
                        )
                        _ = self.store.saveDocument(title: topic.title, audioData: audio, metadata: metadata)
                    }

                    DispatchQueue.main.async { completion(true) }
                } catch {
                    AppLog.shared.add("Bedrock segmentation failed: \(error.localizedDescription)")
                    DispatchQueue.main.async { completion(false) }
                }
            }
        }
    }
}
