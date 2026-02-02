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

                        var mergeItems: [AudioMerger.MergeItem] = []
                        var transcriptParts: [String] = []
                        var pendingSilence = false
                        var hasSpoken = false

                        for seg in topicSegments {
                            let trimmed = seg.text.trimmingCharacters(in: .whitespacesAndNewlines)
                            let isBlank = trimmed.isEmpty || trimmed == "[BLANK_AUDIO]"
                            if isBlank {
                                pendingSilence = true
                                continue
                            }
                            let insertSilence = hasSpoken && pendingSilence
                            mergeItems.append(AudioMerger.MergeItem(audioPath: seg.audioPath, insertSilenceBefore: insertSilence))
                            transcriptParts.append(trimmed)
                            hasSpoken = true
                            pendingSilence = false
                        }

                        guard let audio = self.merger.merge(items: mergeItems, silenceSeconds: 0.5) else { continue }
                        let topicTranscript = transcriptParts.joined(separator: " ")
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
