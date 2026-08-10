import Foundation

// ============================================================
// Proxy Log Scanner —— ~/.tokenwatch/proxy/proxy-*.jsonl
// 代理日志格式与 UsageParser 完全兼容(nested message.usage)
// ============================================================
struct ProxyLogScanner: AgentScanner {
    var id: String { "proxy" }
    let name = "本地代理"
    let description = "TokenWatch 内置代理记录的 API 调用"
    let dataFormat: AgentDataFormat = .jsonlNested

    var searchPaths: [String] {
        ["~/.tokenwatch/proxy/"]
    }

    // 始终可用(不需要安装检测)
    var isInstalled: Bool { true }

    func parse(file: URL) async throws -> [UsageRecord] {
        let content = try String(contentsOf: file, encoding: .utf8)
        // 代理日志的文件名作为 session id
        let sessionID = file.deletingPathExtension().lastPathComponent
        return UsageParser.parseAll(content, sessionID: sessionID, source: "proxy")
    }
}
