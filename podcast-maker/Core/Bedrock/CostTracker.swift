import Foundation

struct HaikuPricing {
    static let modelId = "global.anthropic.claude-haiku-4-5-20251001-v1:0"
    static let inputPerMTok: Double = 1.0
    static let cacheWrite5mPerMTok: Double = 1.25
    static let cacheWrite1hPerMTok: Double = 2.0
    static let cacheHitPerMTok: Double = 0.10
    static let outputPerMTok: Double = 5.0
}

final class CostTracker {
    private let defaults = UserDefaults.standard

    var awsProfile: String {
        get { defaults.string(forKey: DefaultsKey.awsProfile) ?? "" }
        set { defaults.set(newValue, forKey: DefaultsKey.awsProfile) }
    }

    var inputTokens: Int {
        get { defaults.integer(forKey: DefaultsKey.inputTokens) }
        set { defaults.set(newValue, forKey: DefaultsKey.inputTokens) }
    }

    var outputTokens: Int {
        get { defaults.integer(forKey: DefaultsKey.outputTokens) }
        set { defaults.set(newValue, forKey: DefaultsKey.outputTokens) }
    }

    var cacheWrite5mTokens: Int {
        get { defaults.integer(forKey: DefaultsKey.cacheWrite5mTokens) }
        set { defaults.set(newValue, forKey: DefaultsKey.cacheWrite5mTokens) }
    }

    var cacheWrite1hTokens: Int {
        get { defaults.integer(forKey: DefaultsKey.cacheWrite1hTokens) }
        set { defaults.set(newValue, forKey: DefaultsKey.cacheWrite1hTokens) }
    }

    var cacheHitTokens: Int {
        get { defaults.integer(forKey: DefaultsKey.cacheHitTokens) }
        set { defaults.set(newValue, forKey: DefaultsKey.cacheHitTokens) }
    }

    func recordUsage(input: Int, output: Int, cacheWrite5m: Int = 0, cacheWrite1h: Int = 0, cacheHit: Int = 0) {
        inputTokens += input
        outputTokens += output
        cacheWrite5mTokens += cacheWrite5m
        cacheWrite1hTokens += cacheWrite1h
        cacheHitTokens += cacheHit
    }

    func totalCostUSD() -> Double {
        let inputCost = Double(inputTokens) / 1_000_000.0 * HaikuPricing.inputPerMTok
        let outputCost = Double(outputTokens) / 1_000_000.0 * HaikuPricing.outputPerMTok
        let cache5mCost = Double(cacheWrite5mTokens) / 1_000_000.0 * HaikuPricing.cacheWrite5mPerMTok
        let cache1hCost = Double(cacheWrite1hTokens) / 1_000_000.0 * HaikuPricing.cacheWrite1hPerMTok
        let cacheHitCost = Double(cacheHitTokens) / 1_000_000.0 * HaikuPricing.cacheHitPerMTok
        return inputCost + outputCost + cache5mCost + cache1hCost + cacheHitCost
    }
}

extension CostTracker: @unchecked Sendable {}
