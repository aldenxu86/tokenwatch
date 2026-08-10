import Foundation

// ============================================================
// Cursor Scanner —— state.vscdb(SQLite KV 表,key="composers")
// 每个 composer 含 conversation bubbles,bubble 含 token 计数
// ============================================================
struct CursorScanner: AgentScanner {
    let name = "Cursor"
    let description = "Cursor AI IDE"
    let dataFormat: AgentDataFormat = .sqlite

    var searchPaths: [String] {
        [
            "~/Library/Application Support/Cursor/User/globalStorage/state.vscdb",
            "~/.cursor/state.json"
        ]
    }

    func parse(file: URL) async throws -> [UsageRecord] {
        if file.lastPathComponent == "state.json" {
            return try await parseStateJSON(file)
        }
        // vscdb SQLite:暂用 sqlite3 命令行(避免依赖 SQLite 库在未沙盒场景的结构差异)
        return try await parseVSCDB(file)
    }

    private func parseStateJSON(_ url: URL) async throws -> [UsageRecord] {
        let data = try Data(contentsOf: url)
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return [] }

        var records: [UsageRecord] = []
        let month = obj["month"] as? [String: Any] ?? [:]
        let totalTokens = (month["totalTokensUsed"] as? NSNumber)?.intValue ?? 0
        if totalTokens > 0 {
            let ts = Date()
            records.append(UsageRecord(
                id: "cursor-state-\(Int(ts.timeIntervalSince1970))",
                sessionID: "cursor-monthly", source: "cursor",
                timestamp: ts, model: "cursor-default",
                inputTokens: totalTokens / 2,
                outputTokens: totalTokens / 2,
                cacheCreationTokens: 0, cacheReadTokens: 0
            ))
        }
        return records
    }

    private func parseVSCDB(_ url: URL) async throws -> [UsageRecord] {
        // 用 sqlite3 命令行提取 composers 键
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/sqlite3")
        process.arguments = [url.path,
            "SELECT value FROM ItemTable WHERE key='composers' LIMIT 1"]
        let pipe = Pipe()
        process.standardOutput = pipe
        try process.run()
        process.waitUntilExit()

        let outputData = pipe.fileHandleForReading.readDataToEndOfFile()
        guard let jsonStr = String(data: outputData, encoding: .utf8),
              !jsonStr.isEmpty,
              let data = jsonStr.data(using: .utf8),
              let composers = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]]
        else { return [] }

        var records: [UsageRecord] = []
        let sessionID = "cursor-ide"

        for composer in composers {
            let bubbles = composer["bubbles"] as? [[String: Any]] ?? []
            for bubble in bubbles {
                let model = bubble["model"] as? String ?? "cursor"
                let input = (bubble["inputTokens"] as? NSNumber)?.intValue
                    ?? (bubble["prompt_tokens"] as? NSNumber)?.intValue ?? 0
                let output = (bubble["outputTokens"] as? NSNumber)?.intValue
                    ?? (bubble["completion_tokens"] as? NSNumber)?.intValue ?? 0
                guard input > 0 || output > 0 else { continue }

                let ts = (bubble["timestamp"] as? NSNumber).map {
                    var v = $0.doubleValue
                    if v > 1e12 { v /= 1000 }
                    return Date(timeIntervalSince1970: v)
                } ?? Date()

                records.append(UsageRecord(
                    id: "cursor-\(Int(ts.timeIntervalSince1970))-\(input)-\(output)",
                    sessionID: sessionID, source: "cursor",
                    timestamp: ts, model: model,
                    inputTokens: input, outputTokens: output,
                    cacheCreationTokens: 0, cacheReadTokens: 0
                ))
            }
        }
        return records
    }
}
