import Foundation
import Combine

// ============================================================
// 用量数据引擎(ScannerRegistry 驱动)
// - 通过 Registry 发现所有已启用 Agent 的数据文件
// - 记录每个文件的读取偏移 → 每秒增量扫描(实时)
// - 聚合:今日 / 近7日 / 累计 / 按模型 / 按 source / 当前会话
// ============================================================

/// 菜单栏图标显示的统计周期(设置页「显示」Tab 可选,持久化)
enum MenuBarPeriod: String, CaseIterable, Sendable {
    case today = "today"
    case week = "week"
    case all = "all"

    var label: String {
        switch self {
        case .today: return "今日"
        case .week: return "近7日"
        case .all: return "累计"
        }
    }
}

@MainActor
final class UsageStore: ObservableObject {

    // MARK: 发布的状态
    @Published var today: UsageSummary = UsageSummary()
    @Published var week: UsageSummary = UsageSummary()
    @Published var allTime: UsageSummary = UsageSummary()
    @Published var perModel: [(model: String, summary: UsageSummary)] = []
    @Published var perSource: [(source: String, name: String, summary: UsageSummary)] = []
    @Published var perDay: [Date: UsageSummary] = [:]
    @Published var currentSessionID: String = ""
    @Published var currentSession: UsageSummary = UsageSummary()
    @Published var lastScanAt: Date?
    @Published var filesWatched = 0
    @Published var enabledAgentCount = 0
    /// USD→CNY 汇率(汇总金额折算用,启动时异步拉取)
    @Published var usdToCNY: Double = ExchangeRateFetcher.defaultUSDToCNY
    /// 菜单栏图标显示的统计周期(设置页可选,变更即持久化)
    @Published var menuBarPeriod: MenuBarPeriod {
        didSet { UserDefaults.standard.set(menuBarPeriod.rawValue, forKey: Self.menuBarPeriodKey) }
    }

    // MARK: 内部状态
    let registry: ScannerRegistry
    private var priceTable: [String: ModelPricing]
    private var offsets: [String: Int64] = [:]
    private var seenKeys: Set<String> = []
    private var dayAcc: [Date: UsageSummary] = [:]
    private var modelAcc: [String: UsageSummary] = [:]
    private var sourceAcc: [String: UsageSummary] = [:]
    private var sessionAcc: [String: UsageSummary] = [:]
    private var sessionStart: [String: Date] = [:]
    private var timer: Timer?
    private var lastScanTime: Date = .distantPast
    private let scanInterval: TimeInterval = 1.0  // 最小间隔 1s

    private static let offsetsKey = "scanOffsets.v2"
    private static let menuBarPeriodKey = "menuBarPeriod"
    private static let activeWindow: TimeInterval = 24 * 3600

    init(registry: ScannerRegistry? = nil, priceTable: [String: ModelPricing]? = nil) {
        self.registry = registry ?? ScannerRegistry()
        self.priceTable = priceTable ?? Pricing.load()
        self.menuBarPeriod = MenuBarPeriod(rawValue: UserDefaults.standard.string(forKey: Self.menuBarPeriodKey) ?? "") ?? .today
        self.registry.loadCustomScanners()
        loadOffsets()
    }

    private var hasStarted = false

    // MARK: - 生命周期

    func start() {
        guard !hasStarted else { return }
        hasStarted = true
        fullScan()
        Task { [weak self] in
            let rate = await ExchangeRateFetcher.current()
            self?.usdToCNY = rate
        }
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.incrementalScan() }
        }
    }

    func stop() { timer?.invalidate(); timer = nil }
    func refreshNow() { lastScanTime = .distantPast; fullScan() }

    func reloadPricing() {
        priceTable = Pricing.load()
        fullScan()
    }

    // MARK: - 扫描

    private func fullScan() {
        let now = Date()
        guard now.timeIntervalSince(lastScanTime) >= scanInterval else { return }
        lastScanTime = now
        Task.detached(priority: .utility) { [weak self] in
            guard let self else { return }
            let parsed = await self.registry.fullScan()
            let newOffsets = await self.computeOffsets()
            await MainActor.run { [weak self] in
                guard let self else { return }
                self.offsets.merge(newOffsets) { _, new in new }
                self.ingest(parsed, isFull: true)
                self.persistOffsets()
            }
        }
    }

    private func computeOffsets() async -> [String: Int64] {
        var off: [String: Int64] = [:]
        let fm = FileManager.default
        for scanner in registry.scanners where registry.enabledIDs.contains(scanner.id) {
            for url in scanner.discover() {
                let size = (try? fm.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.int64Value ?? 0
                off[url.path] = size
            }
        }
        return off
    }

    private func incrementalScan() {
        let now = Date()
        guard now.timeIntervalSince(lastScanTime) >= scanInterval else { return }
        lastScanTime = now
        let active = registry.activeFiles()
        let off = offsets
        Task.detached(priority: .utility) { [active, off, weak self] in
            guard let self else { return }
            var newOffsets: [String: Int64] = [:]
            var parsed: [(key: String, record: UsageRecord)] = []
            let fm = FileManager.default

            for item in active {
                let path = item.url.path
                let size = (try? fm.attributesOfItem(atPath: path)[.size] as? Int) ?? 0
                let offset = off[path] ?? 0
                guard size >= offset else { newOffsets[path] = 0; continue }
                let start = max(0, offset - 1_048_576)
                guard let fh = try? FileHandle(forReadingFrom: item.url) else { continue }
                defer { try? fh.close() }
                do { try fh.seek(toOffset: UInt64(start)) } catch { continue }
                let data = fh.readDataToEndOfFile()
                guard !data.isEmpty else { newOffsets[path] = Int64(size); continue }
                guard let content = String(data: data, encoding: .utf8) else {
                    newOffsets[path] = Int64(size); continue
                }
                // 单个文件的增量内容:走对应 Scanner 解析(复用 parse 即可)
                if let records = try? await self.scanContent(content, file: item.url, scannerID: item.scannerID) {
                    let sessionID = item.url.deletingPathExtension().lastPathComponent
                    for r in records {
                        parsed.append(("\(item.scannerID)-\(sessionID)-\(r.id)", r))
                    }
                }
                newOffsets[path] = Int64(size)
            }

            await MainActor.run { [parsed, newOffsets] in
                self.offsets.merge(newOffsets) { _, new in new }
                self.ingest(parsed, isFull: false)
                self.lastScanAt = Date()
            }
        }
    }

    private func scanContent(_ content: String, file: URL, scannerID: String) async throws -> [UsageRecord] {
        // 找到对应 Scanner 解析,否则用 UsageParser 兜底
        if let scanner = registry.scanners.first(where: { $0.id == scannerID }) {
            // Scanner 的 parse 需要完整文件,增量场景用 UsageParser 行解析
            let sessionID = file.deletingPathExtension().lastPathComponent
            return UsageParser.parseAll(content, sessionID: sessionID, source: scannerID)
        }
        return []
    }

    // MARK: - 数据吸收

    private func ingest(_ parsed: [(key: String, record: UsageRecord)], isFull: Bool) {
        guard !parsed.isEmpty else { return }  // 无数据不覆盖
        if isFull { resetAccumulators() }

        var newestSession: (id: String, date: Date)?
        for item in parsed {
            let r = item.record
            guard seenKeys.insert(item.key).inserted else { continue }
            let pricing = Pricing.price(for: r.model, table: priceTable)

            let day = Calendar.current.startOfDay(for: r.timestamp)
            dayAcc[day, default: UsageSummary()].add(r, pricing: pricing)
            modelAcc[r.model, default: UsageSummary()].add(r, pricing: pricing)
            sourceAcc[r.source, default: UsageSummary()].add(r, pricing: pricing)
            sessionAcc[r.sessionID, default: UsageSummary()].add(r, pricing: pricing)
            if sessionStart[r.sessionID] == nil || r.timestamp < sessionStart[r.sessionID]! {
                sessionStart[r.sessionID] = r.timestamp
            }
            if !r.sessionID.hasPrefix("proxy-") {
                if newestSession == nil || r.timestamp > newestSession!.date {
                    newestSession = (r.sessionID, r.timestamp)
                }
            }
        }

        let now = Date()
        let todayKey = Calendar.current.startOfDay(for: now)
        today = dayAcc[todayKey] ?? UsageSummary()

        var weekSum = UsageSummary()
        for i in 0..<7 {
            if let d = Calendar.current.date(byAdding: .day, value: -i, to: todayKey),
               let s = dayAcc[d] { weekSum = weekSum + s }
        }
        week = weekSum
        allTime = dayAcc.values.reduce(UsageSummary(), +)

        perModel = modelAcc.map { ($0.key, $0.value) }
            .sorted { $0.1.totalTokens > $1.1.totalTokens }

        perSource = sourceAcc.map { (src, sum) in
            let name = registry.scanners.first(where: { $0.id == src })?.name ?? src
            return (src, name, sum)
        }.sorted { $0.summary.totalTokens > $1.summary.totalTokens }

        var days: [Date: UsageSummary] = [:]
        for i in 0..<30 {
            if let d = Calendar.current.date(byAdding: .day, value: -i, to: todayKey) {
                days[d] = dayAcc[d] ?? UsageSummary()
            }
        }
        perDay = days

        if let ns = newestSession {
            currentSessionID = ns.id
            currentSession = sessionAcc[ns.id] ?? UsageSummary()
        }
        enabledAgentCount = registry.enabledIDs.count
        filesWatched = registry.activeFiles().count
        lastScanAt = Date()
    }

    private func resetAccumulators() {
        dayAcc = [:]
        modelAcc = [:]
        sourceAcc = [:]
        sessionAcc = [:]
        sessionStart = [:]
        seenKeys = []  // 全量刷新时重置去重表
    }

    // MARK: - 偏移持久化

    private func loadOffsets() {
        if let data = UserDefaults.standard.data(forKey: Self.offsetsKey),
           let saved = try? JSONDecoder().decode([String: Int64].self, from: data) {
            offsets = saved
        }
    }

    private func persistOffsets() {
        if let data = try? JSONEncoder().encode(offsets) {
            UserDefaults.standard.set(data, forKey: Self.offsetsKey)
        }
    }
}
