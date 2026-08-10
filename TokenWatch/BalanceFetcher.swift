import Foundation
import Combine

// ============================================================
// 各平台余额/额度查询
// - DeepSeek:官方 GET /user/balance
// - MiniMax:官方 GET /v1/token_plan/remains(中国站)
// - 智谱:社区逆向 GET bigmodel.cn/api/biz/tokenAccounts/list/my(非官方,接口可能变动)
// - 硅基流动:官方 GET /v1/user/info
// - DimLeap / 聚合平台:可自定义余额 URL(通用宽松解析,找不到标准字段则显示原始响应)
// API key 存 Keychain,未配置的平台自动跳过
// ============================================================

/// 一个平台的余额快照
struct ProviderBalance: Identifiable, Sendable {
    let provider: String       // deepseek / minimax / zhipu / aggregator
    let displayName: String
    let summary: String        // 主信息:"$12.34" / "3.2M tokens"
    let detail: String         // 副信息:明细
    let updatedAt: Date
    var id: String { provider }
}

@MainActor
final class BalanceFetcher: ObservableObject {

    @Published var balances: [ProviderBalance] = []
    @Published var isFetching = false
    @Published var lastError: String?

    private var lastFetchAt: Date?

    private let session: URLSession = {
        let cfg = URLSessionConfiguration.default
        cfg.timeoutIntervalForRequest = 15
        return URLSession(configuration: cfg)
    }()

    static let keychainKeys: [String: String] = [
        "deepseek": "provider.deepseek",
        "minimax": "provider.minimax",
        "zhipu": "provider.zhipu",
        "siliconflow": "provider.siliconflow",
        "qwen": "provider.qwen"
    ]

    /// 各平台展示名(设置页也用)
    static let displayNames: [String: String] = [
        "deepseek": "DeepSeek",
        "minimax": "MiniMax",
        "zhipu": "智谱",
        "siliconflow": "硅基流动",
        "qwen": "千问(Qwen)"
    ]

    /// 平台是否支持自定义余额 URL(不存在官方适配器的)
    static func customBalanceURLKey(_ provider: String) -> String {
        "balanceURL.\(provider)"
    }

    /// 某平台是否已配置 key
    static func isConfigured(_ provider: String) -> Bool {
        guard let key = keychainKeys[provider] else { return false }
        return !(KeychainStore.get(key) ?? "").isEmpty
    }

    /// 刷新全部已配置平台的余额(并行);60 秒内重复调用直接跳过
    func refreshAll() async {
        if let last = lastFetchAt, Date().timeIntervalSince(last) < 60 { return }
        lastFetchAt = Date()
        guard !isFetching else { return }
        isFetching = true
        defer { isFetching = false }

        var results: [ProviderBalance] = []
        var errors: [String] = []

        // 并行抓取各平台
        await withTaskGroup(of: ProviderBalance?.self) { group in
            for provider in Self.keychainKeys.keys {
                guard Self.isConfigured(provider) else { continue }
                group.addTask { [self] in await self.fetch(provider) }
            }
            for await result in group {
                if let r = result { results.append(r) }
            }
        }

        // 保留未配置平台的位置标记(展示"未配置")
        for provider in Self.keychainKeys.keys {
            if !Self.isConfigured(provider) {
                results.append(ProviderBalance(
                    provider: provider,
                    displayName: Self.displayNames[provider] ?? provider,
                    summary: "未配置", detail: "在设置中填写 API Key",
                    updatedAt: Date()))
            }
        }

        balances = results.sorted { $0.provider < $1.provider }
        lastError = errors.isEmpty ? nil : errors.joined(separator: "; ")
    }

    // MARK: - 各平台抓取

    private func fetch(_ provider: String) async -> ProviderBalance? {
        let name = Self.displayNames[provider] ?? provider
        // 自定义余额 URL 优先(用户可为任意平台配置)
        if let urlStr = UserDefaults.standard.string(forKey: Self.customBalanceURLKey(provider)),
           let url = URL(string: urlStr), url.host != nil,
           let k = key(provider) {
            return await genericFetch(url: url, apiKey: k, provider: provider, displayName: name)
        }
        do {
            switch provider {
            case "deepseek": return try await fetchDeepSeek()
            case "minimax": return try await fetchMiniMax()
            case "zhipu": return try await fetchZhipu()
            case "siliconflow": return try await fetchSiliconFlow()
            case "qwen": return ProviderBalance(
                provider: provider, displayName: name,
                summary: "需自定义接口", detail: "千问无官方余额 API,在设置中填余额查询 URL",
                updatedAt: Date())
            default: return nil
            }
        } catch {
            return ProviderBalance(
                provider: provider,
                displayName: name,
                summary: "查询失败", detail: error.localizedDescription,
                updatedAt: Date())
        }
    }

    private func getJSON(_ url: URL, apiKey: String) async throws -> [String: Any] {
        var req = URLRequest(url: url)
        req.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        let (data, resp) = try await session.data(for: req)
        guard let http = resp as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        guard (200..<300).contains(http.statusCode),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw NSError(domain: "BalanceFetcher", code: http.statusCode,
                          userInfo: [NSLocalizedDescriptionKey: "HTTP \(http.statusCode) \(body.prefix(120))"])
        }
        return obj
    }

    private func key(_ provider: String) -> String? {
        Self.keychainKeys[provider].flatMap { KeychainStore.get($0) }
    }

    // MARK: DeepSeek — 官方余额接口

    private func fetchDeepSeek() async throws -> ProviderBalance? {
        guard let k = key("deepseek") else { return nil }
        let obj = try await getJSON(URL(string: "https://api.deepseek.com/user/balance")!, apiKey: k)
        let infos = obj["balance_infos"] as? [[String: Any]] ?? []
        let first = infos.first ?? [:]
        let total = first["total_balance"] as? Double ?? 0
        let granted = first["granted_balance"] as? Double ?? 0
        let topped = first["topped_up_balance"] as? Double ?? 0
        let currency = first["currency"] as? String ?? ""
        let symbol = currency == "CNY" ? "¥" : currency == "USD" ? "$" : currency + " "
        return ProviderBalance(
            provider: "deepseek", displayName: "DeepSeek",
            summary: String(format: "%@%.2f", symbol, total),
            detail: "充值 \(symbol)\(String(format: "%.2f", topped)) + 赠送 \(symbol)\(String(format: "%.2f", granted))",
            updatedAt: Date())
    }

    // MARK: MiniMax — 官方 Token Plan 余额(CNY)

    private func fetchMiniMax() async throws -> ProviderBalance? {
        guard let k = key("minimax") else { return nil }
        let obj = try await getJSON(URL(string: "https://api.minimaxi.com/v1/token_plan/remains")!, apiKey: k)

        func pick(_ names: [String]) -> Int? {
            for n in names {
                if let v = obj[n] as? NSNumber { return v.intValue }
            }
            return nil
        }

        let remaining = pick(["remaining_tokens", "remaining_count", "points_balance"])
            ?? pick(["current_interval_usage_count"])
        let used = pick(["used_tokens", "used_count"])
        let reset = obj["reset_time"] as? NSNumber
        let resetText = reset.map { " 重置 \(Date(timeIntervalSince1970: $0.doubleValue).formatted(date: .omitted, time: .shortened))" } ?? ""

        var summary = "未解析到额度"
        if let remaining {
            summary = Format.tokens(remaining) + " 剩余"
            if let used { summary += " · 已用 " + Format.tokens(used) }
        }
        return ProviderBalance(
            provider: "minimax", displayName: "MiniMax",
            summary: summary,
            detail: "token_plan/remains\(resetText)",
            updatedAt: Date())
    }

    // MARK: 智谱 — 社区逆向资源包余额(非官方)

    private func fetchZhipu() async throws -> ProviderBalance? {
        guard let k = key("zhipu") else { return nil }
        let url = URL(string: "https://bigmodel.cn/api/biz/tokenAccounts/list/my?pageNum=1&pageSize=50")!
        let obj = try await getJSON(url, apiKey: k)
        let rows = obj["data"] as? [String: Any]
        let list = rows?["rows"] as? [[String: Any]] ?? []
        guard !list.isEmpty else {
            throw NSError(domain: "BalanceFetcher", code: -1,
                          userInfo: [NSLocalizedDescriptionKey: "无资源包数据(可能 key 无效)"])
        }

        var parts: [String] = []
        var totalTokens = 0
        for row in list.prefix(3) {
            let name = row["resourcePackageName"] as? String ?? "资源包"
            let balance = (row["tokenBalance"] as? NSNumber)?.intValue ?? 0
            let magnitude = (row["tokensMagnitude"] as? NSNumber)?.intValue ?? 1
            let tokens = balance * magnitude
            totalTokens += tokens
            parts.append("\(name): \(Format.tokens(tokens))")
        }
        return ProviderBalance(
            provider: "zhipu", displayName: "智谱",
            summary: Format.tokens(totalTokens) + " 剩余",
            detail: parts.joined(separator: " · "),
            updatedAt: Date())
    }

    // MARK: 硅基流动 — 官方用户信息接口

    private func fetchSiliconFlow() async throws -> ProviderBalance? {
        guard let k = key("siliconflow") else { return nil }
        let obj = try await getJSON(URL(string: "https://api.siliconflow.cn/v1/user/info")!, apiKey: k)
        let data = obj["data"] as? [String: Any] ?? obj
        let total = doubleValue(data["totalBalance"]) ?? 0
        let charged = doubleValue(data["chargeBalance"]) ?? 0
        let bonus = doubleValue(data["balance"]) ?? 0
        return ProviderBalance(
            provider: "siliconflow", displayName: "硅基流动",
            summary: String(format: "¥%.2f", total),
            detail: "充值 ¥\(String(format: "%.2f", charged)) + 赠送 ¥\(String(format: "%.2f", bonus))",
            updatedAt: Date())
    }

    // MARK: 自定义余额 URL — 通用宽松解析(DimLeap 等)

    /// 自定义接口:GET 后尝试从响应中提取常见余额字段,
    /// 提取不到则显示原始响应摘要
    private func genericFetch(url: URL, apiKey: String, provider: String,
                              displayName: String) async -> ProviderBalance? {
        do {
            let obj = try await getJSON(url, apiKey: apiKey)
            let extracted = summarizeRaw(obj)
            return ProviderBalance(
                provider: provider, displayName: displayName,
                summary: extracted.summary, detail: extracted.detail,
                updatedAt: Date())
        } catch {
            return ProviderBalance(
                provider: provider, displayName: displayName,
                summary: "查询失败", detail: error.localizedDescription,
                updatedAt: Date())
        }
    }

    /// 宽松提取:优先 data 子对象,按常见字段名找数字;无命中则显示原始 JSON
    private func summarizeRaw(_ obj: [String: Any]) -> (summary: String, detail: String) {
        let data = (obj["data"] as? [String: Any]) ?? obj
        let numericKeys = [
            ("totalBalance", "总余额"), ("total_balance", "总余额"),
            ("balance", "余额"), ("remaining_tokens", "剩余tokens"),
            ("remaining", "剩余"), ("credits", "点数"), ("credit", "点数"),
            ("usage", "已用($)"), ("used", "已用"), ("limit", "额度")
        ]
        var parts: [String] = []
        for (key, label) in numericKeys {
            if let n = doubleValue(data[key]) {
                parts.append("\(label): \(Self.fmtNum(n))")
            }
        }
        if let first = parts.first {
            return (first, parts.dropFirst().joined(separator: " · "))
        }
        if let raw = try? JSONSerialization.data(withJSONObject: obj, options: [.sortedKeys]),
           let s = String(data: raw, encoding: .utf8) {
            return ("未识别字段", String(s.prefix(160)))
        }
        return ("未识别字段", "")
    }

    private static func fmtNum(_ n: Double) -> String {
        n >= 1000 || n == 0 ? String(format: "%.2f", n) : String(format: "%.4f", n)
    }

    private func doubleValue(_ v: Any?) -> Double? {
        if let n = v as? NSNumber { return n.doubleValue }
        if let s = v as? String, let d = Double(s) { return d }
        return nil
    }

    // MARK: 聚合平台 — 默认 OpenRouter 格式

    private func fetchAggregator() async throws -> ProviderBalance? {
        guard let k = key("aggregator") else { return nil }
        let obj = try await getJSON(URL(string: "https://openrouter.ai/api/v1/auth/key")!, apiKey: k)
        let data = obj["data"] as? [String: Any] ?? [:]
        let usage = (data["usage"] as? NSNumber)?.doubleValue ?? 0
        let limit = (data["limit"] as? NSNumber)?.doubleValue
        let isFree = data["is_free_tier"] as? Bool ?? false

        var summary = String(format: "已用 $%.2f", usage)
        if let limit, limit > 0 {
            summary = String(format: "$%.2f / $%.2f", usage, limit)
        }
        if isFree { summary += " (免费档)" }
        return ProviderBalance(
            provider: "aggregator", displayName: "聚合平台",
            summary: summary,
            detail: "OpenRouter 格式 · 若平台不同请在设置中适配",
            updatedAt: Date())
    }
}
