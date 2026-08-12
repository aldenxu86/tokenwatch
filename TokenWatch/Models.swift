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
    /// 按币种分账(不同币种金额不能直接相加)
    var costByCurrency: [String: Double] = [:]
    var requestCount = 0

    var totalTokens: Int { totalInput + totalOutput + totalCacheCreation + totalCacheRead }

    /// 原始合计(未折算;仅单币种上下文可用,汇总显示请用 cost(in:usdRate:))
    var totalCost: Double { costByCurrency.values.reduce(0, +) }

    /// 折算为指定币种的合计。CNY 目标:USD × usdRate,其余币种按 1:1
    /// (当前模型表只有 USD/CNY 两种币种)
    func cost(in target: String, usdRate: Double) -> Double {
        guard target.uppercased() == "CNY" else { return totalCost }
        return costByCurrency.reduce(0) { sum, item in
            let (currency, amount) = item
            switch currency.uppercased() {
            case "USD": return sum + amount * usdRate
            default: return sum + amount
            }
        }
    }

    mutating func add(_ r: UsageRecord, pricing: ModelPricing) {
        totalInput += r.inputTokens
        totalOutput += r.outputTokens
        totalCacheCreation += r.cacheCreationTokens
        totalCacheRead += r.cacheReadTokens
        let currency = pricing.currency.isEmpty ? "USD" : pricing.currency
        costByCurrency[currency, default: 0] += r.estimatedCost(using: pricing)
        requestCount += 1
    }

    static func + (lhs: UsageSummary, rhs: UsageSummary) -> UsageSummary {
        var s = lhs
        s.totalInput += rhs.totalInput
        s.totalOutput += rhs.totalOutput
        s.totalCacheCreation += rhs.totalCacheCreation
        s.totalCacheRead += rhs.totalCacheRead
        s.requestCount += rhs.requestCount
        for (currency, amount) in rhs.costByCurrency {
            s.costByCurrency[currency, default: 0] += amount
        }
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
