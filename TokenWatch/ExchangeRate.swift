import Foundation

// ============================================================
// USD→CNY 汇率(自动获取 + 兜底)
// - 双源:open.er-api.com(无 key)→ api.frankfurter.app(ECB 数据)
// - 结果缓存 6 小时;全部失败回退过期缓存 → 默认值 7.2
// 供汇总金额折算使用(见 UsageSummary.cost(in:usdRate:))
// ============================================================
enum ExchangeRateFetcher {

    static let defaultUSDToCNY = 7.2
    private static let rateKey = "usdToCNYRate"
    private static let rateAtKey = "usdToCNYRateAt"
    private static let cacheLifetime: TimeInterval = 6 * 3600

    private static let session: URLSession = {
        let cfg = URLSessionConfiguration.default
        cfg.timeoutIntervalForRequest = 10
        return URLSession(configuration: cfg)
    }()

    /// 当前可用汇率:新鲜缓存 → 拉取 → 过期缓存 → 默认值
    static func current() async -> Double {
        if let (rate, at) = cached(), Date().timeIntervalSince(at) < cacheLifetime {
            return rate
        }
        if let rate = await fetch() {
            save(rate)
            return rate
        }
        return cached()?.rate ?? defaultUSDToCNY
    }

    /// 强制刷新(失败返回旧值)
    static func refresh() async -> Double {
        if let rate = await fetch() {
            save(rate)
            return rate
        }
        return cached()?.rate ?? defaultUSDToCNY
    }

    // MARK: - 拉取

    private static func fetch() async -> Double? {
        // 1. er-api.com: {"result":"success","rates":{"CNY":7.17}}
        if let r = await rate(from: "https://open.er-api.com/v6/latest/USD",
                              cnyKey: "CNY") { return r }
        // 2. frankfurter.app(ECB): {"rates":{"CNY":7.17},"base":"USD"}
        if let r = await rate(from: "https://api.frankfurter.app/latest?from=USD&to=CNY",
                              cnyKey: "CNY") { return r }
        return nil
    }

    private static func rate(from urlString: String, cnyKey: String) async -> Double? {
        guard let url = URL(string: urlString) else { return nil }
        do {
            let (data, resp) = try await session.data(from: url)
            guard let http = resp as? HTTPURLResponse,
                  (200..<300).contains(http.statusCode),
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let rates = obj["rates"] as? [String: Any],
                  let v = rates[cnyKey] as? NSNumber
            else { return nil }
            return v.doubleValue
        } catch {
            return nil
        }
    }

    // MARK: - 缓存(UserDefaults)

    static func cached() -> (rate: Double, at: Date)? {
        let def = UserDefaults.standard
        guard let r = def.object(forKey: rateKey) as? Double,
              let t = def.object(forKey: rateAtKey) as? Date
        else { return nil }
        return (r, t)
    }

    static func save(_ rate: Double) {
        let def = UserDefaults.standard
        def.set(rate, forKey: rateKey)
        def.set(Date(), forKey: rateAtKey)
    }
}
