import Foundation

// ============================================================
// 模型单价配置(默认值为估算,可在设置里修改)
// 货币规则:
//   国际 Agent(Claude Code/Codex/Cursor/Gemini CLI) → USD
//   国内 Agent(DeepSeek/WorkBuddy/CodeBuddy/Qoder/Trae) → CNY
//   API 余额跟随平台:硅基流动/智谱/MiniMax → CNY,OpenRouter → USD
// ============================================================
enum Pricing {

    static let defaultPrices: [String: ModelPricing] = [
        // Claude 系列(Anthropic 官方,$)
        "claude-sonnet-5":    ModelPricing(inputPerMillion: 3.0, outputPerMillion: 15.0,
                                           cacheReadPerMillion: 0.30, currency: "USD"),
        "claude-opus-5":      ModelPricing(inputPerMillion: 5.0, outputPerMillion: 25.0,
                                           cacheReadPerMillion: 0.50, currency: "USD"),
        "claude-haiku-4-5":   ModelPricing(inputPerMillion: 0.80, outputPerMillion: 4.0, currency: "USD"),
        // Codex / OpenAI 系列($)
        "codex":              ModelPricing(inputPerMillion: 2.5, outputPerMillion: 10.0, currency: "USD"),
        "gpt-5":              ModelPricing(inputPerMillion: 2.5, outputPerMillion: 10.0, currency: "USD"),
        "gpt-4o":             ModelPricing(inputPerMillion: 2.5, outputPerMillion: 10.0, currency: "USD"),
        "o4-mini":            ModelPricing(inputPerMillion: 1.1, outputPerMillion: 4.4, currency: "USD"),
        // Gemini 系列($)
        "gemini-3-flash":     ModelPricing(inputPerMillion: 0.15, outputPerMillion: 0.60, currency: "USD"),
        "gemini-3-pro":       ModelPricing(inputPerMillion: 1.25, outputPerMillion: 5.0, currency: "USD"),
        // DeepSeek 系列(¥)
        "deepseek-v4-flash":  ModelPricing(inputPerMillion: 1.0, outputPerMillion: 2.0, currency: "CNY"),
        "deepseek-v4-pro":    ModelPricing(inputPerMillion: 2.0, outputPerMillion: 8.0, currency: "CNY"),
        "deepseek-chat":      ModelPricing(inputPerMillion: 1.0, outputPerMillion: 2.0, currency: "CNY"),
        "deepseek-reasoner":  ModelPricing(inputPerMillion: 4.0, outputPerMillion: 16.0, currency: "CNY"),
        // 国内 Agent 模型(¥)
        "workbuddy":          ModelPricing(inputPerMillion: 1.0, outputPerMillion: 3.0, currency: "CNY"),
        "codebuddy":          ModelPricing(inputPerMillion: 1.0, outputPerMillion: 3.0, currency: "CNY"),
        "cursor":             ModelPricing(inputPerMillion: 3.0, outputPerMillion: 15.0, currency: "USD"),
        // 未知(默认 ¥)
        "unknown":            ModelPricing(inputPerMillion: 1.0, outputPerMillion: 3.0, currency: "CNY"),
    ]

    /// 按 Agent source 返回默认货币(用于没有明确模型名的汇总)
    static func currencyForAgent(_ source: String) -> String {
        switch source {
        case "claude-code", "codex", "cursor", "gemini": return "USD"
        case "deepseek", "workbuddy", "codebuddy", "zhipu",
             "siliconflow", "minimax", "trae-intl", "trae-cn", "qoder": return "CNY"
        default: return "CNY"
        }
    }

    static let storageKey = "modelPricings"

    static func load() -> [String: ModelPricing] {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let saved = try? JSONDecoder().decode([String: ModelPricing].self, from: data)
        else { return defaultPrices }
        return defaultPrices.merging(saved) { _, new in new }
    }

    static func save(_ prices: [String: ModelPricing]) {
        if let data = try? JSONEncoder().encode(prices) {
            UserDefaults.standard.set(data, forKey: storageKey)
        }
    }

    static func price(for model: String, table: [String: ModelPricing]) -> ModelPricing {
        table[model] ?? table["unknown"]
            ?? ModelPricing(inputPerMillion: 1.0, outputPerMillion: 3.0, currency: "CNY")
    }
}
