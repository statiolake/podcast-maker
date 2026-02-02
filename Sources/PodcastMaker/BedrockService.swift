import Foundation
import AWSBedrockRuntime
import AWSSDKIdentity

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

    init(tracker: CostTracker) {
        self.tracker = tracker
        self.region = ProcessInfo.processInfo.environment["AWS_REGION"] ?? "us-east-1"
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

    private func invoke(prompt: String, profile: String) async throws -> (text: String, usage: BedrockUsage) {
        if !profile.isEmpty {
            setenv("AWS_PROFILE", profile, 1)
        }

        var config = try await BedrockRuntimeClient.BedrockRuntimeClientConfiguration(region: region)
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
        inference.maxTokens = 200
        inference.temperature = 0.2

        let input = ConverseInput(
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
}
