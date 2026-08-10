import Foundation

// ============================================================
// 数据模型
// ============================================================

/// 一条 API 用量记录(从会话 transcript / 代理日志 / Agent Scanner 解析)
struct UsageRecord: Identifiable, Sendable {
    let id: String
    let sessionID: String
    let source: String           // "claude-code" / "codex" / "cursor" / "proxy" 等
    let timestamp: Date
    let model: String
    let inputTokens: Int
    let outputTokens: Int
    let cacheCreationTokens: Int
    let cacheReadTokens: Int

    /// 估算费用(美元)
    func estimatedCost(using pricing: ModelPricing) -> Double {
        pricing.cost(input: inputTokens, output: outputTokens,
                     cacheCreation: cacheCreationTokens, cacheRead: cacheReadTokens)
    }
}

/// 模型单价(每百万 token) + 货币单位
struct ModelPricing: Codable, Sendable {
    var inputPerMillion: Double
    var outputPerMillion: Double
    var cacheWritePerMillion: Double
    var cacheReadPerMillion: Double
    var currency: String           // "USD" / "CNY" / "EUR" 等

    init(inputPerMillion: Double, outputPerMillion: Double,
         cacheWritePerMillion: Double? = nil, cacheReadPerMillion: Double? = nil,
         currency: String = "USD") {
        self.inputPerMillion = inputPerMillion
        self.outputPerMillion = outputPerMillion
        self.cacheWritePerMillion = cacheWritePerMillion ?? inputPerMillion
        self.cacheReadPerMillion = cacheReadPerMillion ?? inputPerMillion * 0.1
        self.currency = currency
    }

    func cost(input: Int, output: Int, cacheCreation: Int, cacheRead: Int) -> Double {
        (Double(input) / 1e6) * inputPerMillion
            + (Double(output) / 1e6) * outputPerMillion
            + (Double(cacheCreation) / 1e6) * cacheWritePerMillion
            + (Double(cacheRead) / 1e6) * cacheReadPerMillion
    }
}

/// 聚合统计
struct UsageSummary: Sendable {
    var totalInput = 0
    var totalOutput = 0
    var totalCacheCreation = 0
    var totalCacheRead = 0
    var totalCost = 0.0
    var requestCount = 0

    var totalTokens: Int { totalInput + totalOutput + totalCacheCreation + totalCacheRead }

    mutating func add(_ r: UsageRecord, pricing: ModelPricing) {
        totalInput += r.inputTokens
        totalOutput += r.outputTokens
        totalCacheCreation += r.cacheCreationTokens
        totalCacheRead += r.cacheReadTokens
        totalCost += r.estimatedCost(using: pricing)
        requestCount += 1
    }

    static func + (lhs: UsageSummary, rhs: UsageSummary) -> UsageSummary {
        var s = lhs
        s.totalInput += rhs.totalInput
        s.totalOutput += rhs.totalOutput
        s.totalCacheCreation += rhs.totalCacheCreation
        s.totalCacheRead += rhs.totalCacheRead
        s.totalCost += rhs.totalCost
        s.requestCount += rhs.requestCount
        return s
    }
}

// ============================================================
// 格式化辅助
// ============================================================
enum Format {
    /// 1234 → "1.2k", 2345678 → "2.3M"
    static func tokens(_ n: Int) -> String {
        let d = Double(n)
        if d >= 1_000_000 { return String(format: "%.1fM", d / 1_000_000) }
        if d >= 1_000 { return String(format: "%.1fk", d / 1_000) }
        return "\(n)"
    }

    /// 费用(按货币符号)
    static func cost(_ c: Double, currency: String = "USD") -> String {
        let sym = currencySymbol(currency)
        return c >= 1.0 ? String(format: "%@%.2f", sym, c) : String(format: "%@%.4f", sym, c)
    }

    /// 货币代码 → 符号
    static func currencySymbol(_ code: String) -> String {
        switch code.uppercased() {
        case "CNY", "RMB": return "¥"
        case "USD": return "$"
        case "EUR": return "€"
        case "GBP": return "£"
        case "JPY": return "¥"
        default: return code + " "
        }
    }
}
