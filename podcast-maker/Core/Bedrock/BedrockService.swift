import Foundation

import AWSBedrockRuntime
import AWSSDKIdentity
import Smithy

@_spi(SmithyDocumentImpl) import struct Smithy.StringMapDocument
@_spi(SmithyDocumentImpl) import struct Smithy.StringDocument
@_spi(SmithyDocumentImpl) import struct Smithy.IntegerDocument

struct BedrockUsage {
    let inputTokens: Int
    let outputTokens: Int
    let cacheWrite5mTokens: Int
    let cacheWrite1hTokens: Int
    let cacheHitTokens: Int
}

final class BedrockService {
    private let tracker: CostTracker
    private let region: String
    private let thinkingBudgetTokens: Int

    init(tracker: CostTracker, thinkingBudgetTokens: Int = 4000) {
        self.tracker = tracker
        self.region = ProcessInfo.processInfo.environment["AWS_REGION"] ?? "us-east-1"
        self.thinkingBudgetTokens = thinkingBudgetTokens
    }

    func test(prompt: String, profile: String) async throws -> String {
        AppLog.shared.add("Bedrock test started (profile=\(profile.isEmpty ? "default" : profile))")
        let response = try await invoke(prompt: prompt, profile: profile)
        tracker.recordUsage(
            input: response.usage.inputTokens,
            output: response.usage.outputTokens,
            cacheWrite5m: response.usage.cacheWrite5mTokens,
            cacheWrite1h: response.usage.cacheWrite1hTokens,
            cacheHit: response.usage.cacheHitTokens
        )
        AppLog.shared.add("Bedrock test succeeded (input=\(response.usage.inputTokens), output=\(response.usage.outputTokens))")
        return response.text
    }

    func invokeRaw(prompt: String, profile: String) async throws -> String {
        let response = try await invoke(prompt: prompt, profile: profile)
        tracker.recordUsage(
            input: response.usage.inputTokens,
            output: response.usage.outputTokens,
            cacheWrite5m: response.usage.cacheWrite5mTokens,
            cacheWrite1h: response.usage.cacheWrite1hTokens,
            cacheHit: response.usage.cacheHitTokens
        )
        return response.text
    }

    private func invoke(prompt: String, profile: String) async throws -> (text: String, usage: BedrockUsage) {
        if !profile.isEmpty {
            setenv("AWS_PROFILE", profile, 1)
        }

        let config = try await BedrockRuntimeClient.BedrockRuntimeClientConfiguration(region: region)
        if !profile.isEmpty {
            let resolver = ProfileAWSCredentialIdentityResolver(profileName: profile)
            config.awsCredentialIdentityResolver = resolver
        }

        let client = BedrockRuntimeClient(config: config)
        let message = BedrockRuntimeClientTypes.Message(
            content: [.text(prompt)],
            role: .user
        )

        var inference = BedrockRuntimeClientTypes.InferenceConfiguration()
        inference.maxTokens = 10_000

        let input = ConverseInput(
            additionalModelRequestFields: thinkingConfig(),
            inferenceConfig: inference,
            messages: [message],
            modelId: HaikuPricing.modelId
        )

        let output = try await client.converse(input: input)

        let text: String
        if let response = output.output {
            switch response {
            case .message(let message):
                text = message.content?.compactMap { block in
                    switch block {
                    case .text(let value): return value
                    default: return nil
                    }
                }.joined() ?? ""
            case .sdkUnknown:
                text = ""
            }
        } else {
            text = ""
        }

        let usage = BedrockUsage(
            inputTokens: Int(output.usage?.inputTokens ?? 0),
            outputTokens: Int(output.usage?.outputTokens ?? 0),
            cacheWrite5mTokens: 0,
            cacheWrite1hTokens: 0,
            cacheHitTokens: 0
        )

        return (text: text, usage: usage)
    }

    private func thinkingConfig() -> Smithy.Document {
        let thinking = StringMapDocument(value: [
            "type": StringDocument(value: "enabled"),
            "budget_tokens": IntegerDocument(value: thinkingBudgetTokens)
        ])
        let root = StringMapDocument(value: [
            "thinking": thinking
        ])
        return Smithy.Document(root)
    }
}

extension BedrockService: @unchecked Sendable {}
