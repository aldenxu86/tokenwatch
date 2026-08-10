import Foundation

// ============================================================
// ScannerRegistry —— 管理所有 Agent Scanner
// 提供给 UsageStore 统一的扫描接口
// ============================================================
@MainActor
final class ScannerRegistry: ObservableObject {
    @Published var scanners: [any AgentScanner] = []
    @Published var enabledIDs: Set<String> = []

    /// 默认启用的 Scanner(预置,自动检测安装)
    private static let defaults: [any AgentScanner] = [
        ClaudeCodeScanner(),
        CodexScanner(),
        CursorScanner(),
        ProxyLogScanner(),
        CodeBuddyScanner(),
        WorkBuddyScanner(),
        TraeScanner(),
        TraeCNScanner(),
        TraeWorkCNScanner(),
        QoderWorkCNScanner()
        // GenericJSONLScanner 由用户手动添加,不预置
    ]

    private let enabledKey = "enabledScanners"

    init() {
        scanners = Self.defaults
        // 恢复用户启停配置(UserDefaults)
        if let saved = UserDefaults.standard.stringArray(forKey: enabledKey) {
            enabledIDs = Set(saved)
        } else {
            // 首次启动:默认启用所有已安装的 + Proxy(始终可用)
            for s in Self.defaults {
                if s.id == "proxy" || s.isInstalled { enabledIDs.insert(s.id) }
            }
        }
    }

    /// 扫描全部已启用 Scanner 的所有文件,返回 UsageRecord 列表
    func fullScan() async -> [(key: String, record: UsageRecord)] {
        var results: [(key: String, record: UsageRecord)] = []
        for scanner in scanners where enabledIDs.contains(scanner.id) {
            let files = scanner.discover()
            for file in files {
                guard let records = try? await scanner.parse(file: file) else { continue }
                let sessionID = file.deletingPathExtension().lastPathComponent
                for r in records {
                    let key = "\(scanner.id)-\(sessionID)-\(r.id)"
                    results.append((key, r))
                }
            }
        }
        return results
    }

    /// 增量扫描:只返回指定文件的记录(文件级别偏移由 UsageStore 管理)
    func scanFiles(_ files: [(scannerID: String, url: URL)]) async -> [(key: String, record: UsageRecord)] {
        var results: [(key: String, record: UsageRecord)] = []
        for item in files {
            guard let scanner = scanners.first(where: { $0.id == item.scannerID }) else { continue }
            guard let records = try? await scanner.parse(file: item.url) else { continue }
            let sessionID = item.url.deletingPathExtension().lastPathComponent
            for r in records {
                let key = "\(scanner.id)-\(sessionID)-\(r.id)"
                results.append((key, r))
            }
        }
        return results
    }

    /// 活跃文件(24h 内有写入)
    func activeFiles() -> [(scannerID: String, url: URL)] {
        let cutoff = Date().addingTimeInterval(-24 * 3600)
        let fm = FileManager.default
        var result: [(String, URL)] = []
        for scanner in scanners where enabledIDs.contains(scanner.id) {
            for url in scanner.discover() {
                let mod = (try? fm.attributesOfItem(atPath: url.path)[.modificationDate] as? Date)
                if let m = mod, m >= cutoff {
                    result.append((scanner.id, url))
                }
            }
        }
        return result
    }

    /// 保存用户启停配置
    func toggle(_ scannerID: String, on: Bool) {
        if on { enabledIDs.insert(scannerID) }
        else { enabledIDs.remove(scannerID) }
        UserDefaults.standard.set(Array(enabledIDs), forKey: enabledKey)
    }

    /// 添加自定义 Scanner(从用户配置构建)
    func addCustom(name: String, paths: [String], format: AgentDataFormat) {
		objectWillChange.send()
        let custom = GenericJSONLScanner(customName: name, customPaths: paths)
        scanners.append(custom)
        enabledIDs.insert(custom.id)
        UserDefaults.standard.set(Array(enabledIDs), forKey: enabledKey)
        // 持久化自定义 Scanner
        saveCustomScanners()
    }

    /// 移除自定义 Scanner
    func removeCustom(_ scannerID: String) {
        scanners.removeAll { $0.id == scannerID }
        enabledIDs.remove(scannerID)
        UserDefaults.standard.set(Array(enabledIDs), forKey: enabledKey)
        saveCustomScanners()
    }

    var customScannerCount: Int { scanners.filter { $0.id.hasPrefix("custom-") }.count }

    // MARK: 持久化自定义 Scanner

    private static let customScannersKey = "customScanners"

    private func saveCustomScanners() {
        var customs: [[String: Any]] = []
        for s in scanners where s.id.hasPrefix("custom-") {
            guard let g = s as? GenericJSONLScanner else { continue }
            customs.append(["name": g.name, "paths": g.searchPaths, "format": g.dataFormat.rawValue])
        }
        UserDefaults.standard.set(customs, forKey: Self.customScannersKey)
    }

    func loadCustomScanners() {
        guard let customs = UserDefaults.standard.array(forKey: Self.customScannersKey) as? [[String: Any]]
        else { return }
        for c in customs {
            guard let name = c["name"] as? String,
                  let paths = c["paths"] as? [String],
                  let fmtStr = c["format"] as? String,
                  let fmt = AgentDataFormat(rawValue: fmtStr)
            else { continue }
            let s = GenericJSONLScanner(customName: name, customPaths: paths)
            scanners.append(s)
            if enabledIDs.contains(s.id) == false { enabledIDs.insert(s.id) }
        }
    }
}
