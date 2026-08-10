import Foundation

// ============================================================
// Trae / Trae CN Scanner
// 国际版: ~/Library/Application Support/Trae/
// 国内版: ~/Library/Application Support/Trae CN/
// 注意:主会话数据在 ModularData/ai-agent/database.db(SQLCipher4 加密),
//      无法直接读取。state.vscdb 可能含部分元数据,尽力提取。
// ============================================================
struct TraeScanner: AgentScanner {
    var id: String { "trae-intl" }
    let name = "Trae 国际版"
    let description = "字节跳动 Trae IDE(国际版)"
    let dataFormat: AgentDataFormat = .sqlite

    var searchPaths: [String] {
        ["~/Library/Application Support/Trae/User/globalStorage/state.vscdb"]
    }

    func parse(file: URL) async throws -> [UsageRecord] {
        return try await parseVSCDB(file)
    }

    private func parseVSCDB(_ url: URL) async throws -> [UsageRecord] {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/sqlite3")
        process.arguments = [url.path,
            "SELECT value FROM ItemTable WHERE key LIKE '%ai-agent%' OR key LIKE '%chat%' OR key LIKE '%token%' LIMIT 50"]
        let pipe = Pipe()
        process.standardOutput = pipe
        try process.run()
        process.waitUntilExit()

        let outputData = pipe.fileHandleForReading.readDataToEndOfFile()
        guard let text = String(data: outputData, encoding: .utf8), !text.isEmpty
        else { return [] }

        var records: [UsageRecord] = []
        let lines = text.components(separatedBy: .newlines)
        for line in lines {
            guard let data = line.data(using: .utf8),
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            else { continue }
            // 尝试递归查找 token 信息
            extractTokens(from: obj, into: &records)
        }
        return records
    }

    private func extractTokens(from obj: [String: Any], into records: inout [UsageRecord]) {
        // 查找 usage / token_usage 字段
        for key in ["usage", "token_usage", "tokenUsage", "tokens"] {
            if let u = obj[key] as? [String: Any] {
                let input = (u["input_tokens"] as? NSNumber)?.intValue
                    ?? (u["inputTokens"] as? NSNumber)?.intValue
                    ?? (u["prompt_tokens"] as? NSNumber)?.intValue ?? 0
                let output = (u["output_tokens"] as? NSNumber)?.intValue
                    ?? (u["outputTokens"] as? NSNumber)?.intValue
                    ?? (u["completion_tokens"] as? NSNumber)?.intValue ?? 0
                if input > 0 || output > 0 {
                    let model = (obj["model"] as? String) ?? "trae"
                    var date = Date()
                    if let ts = obj["timestamp"] as? NSNumber {
                        var v = ts.doubleValue
                        if v > 1e12 { v /= 1000 }
                        date = Date(timeIntervalSince1970: v)
                    }
                    records.append(UsageRecord(
                        id: "trae-\(Int(date.timeIntervalSince1970))-\(input)-\(output)",
                        sessionID: "trae-intl", source: "trae-intl",
                        timestamp: date, model: model,
                        inputTokens: input, outputTokens: output,
                        cacheCreationTokens: (u["cache_creation_input_tokens"] as? NSNumber)?.intValue ?? 0,
                        cacheReadTokens: (u["cache_read_input_tokens"] as? NSNumber)?.intValue ?? 0))
                    return
                }
            }
        }
        // 递归嵌套对象
        for (_, v) in obj {
            if let nested = v as? [String: Any] { extractTokens(from: nested, into: &records) }
            else if let arr = v as? [[String: Any]] {
                for item in arr { extractTokens(from: item, into: &records) }
            }
        }
    }
}

// ============================================================
// Trae CN(国内版)
// ============================================================
struct TraeCNScanner: AgentScanner {
    var id: String { "trae-cn" }
    let name = "Trae 国内版"
    let description = "字节跳动 Trae IDE(国内版)"
    let dataFormat: AgentDataFormat = .sqlite

    var searchPaths: [String] {
        ["~/Library/Application Support/Trae CN/User/globalStorage/state.vscdb"]
    }

    func parse(file: URL) async throws -> [UsageRecord] {
        // 复用 TraeScanner 的 vscdb 解析
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/sqlite3")
        process.arguments = [file.path,
            "SELECT value FROM ItemTable WHERE key LIKE '%ai-agent%' OR key LIKE '%chat%' OR key LIKE '%token%' LIMIT 50"]
        let pipe = Pipe()
        process.standardOutput = pipe
        try process.run()
        process.waitUntilExit()

        let outputData = pipe.fileHandleForReading.readDataToEndOfFile()
        guard let text = String(data: outputData, encoding: .utf8), !text.isEmpty
        else { return [] }

        var records: [UsageRecord] = []
        for line in text.components(separatedBy: .newlines) {
            guard let data = line.data(using: .utf8),
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            else { continue }
            extractTokens(obj: obj, records: &records, source: "trae-cn")
        }
        return records
    }

    private func extractTokens(obj: [String: Any], records: inout [UsageRecord], source: String) {
        for key in ["usage", "token_usage", "tokenUsage", "tokens"] {
            guard let u = obj[key] as? [String: Any] else { continue }
            let input = (u["input_tokens"] as? NSNumber)?.intValue
                ?? (u["inputTokens"] as? NSNumber)?.intValue
                ?? (u["prompt_tokens"] as? NSNumber)?.intValue ?? 0
            let output = (u["output_tokens"] as? NSNumber)?.intValue
                ?? (u["outputTokens"] as? NSNumber)?.intValue
                ?? (u["completion_tokens"] as? NSNumber)?.intValue ?? 0
            if input > 0 || output > 0 {
                records.append(UsageRecord(
                    id: "traecn-\(Int(Date().timeIntervalSince1970))-\(input)-\(output)",
                    sessionID: "trae-cn", source: source,
                    timestamp: Date(), model: (obj["model"] as? String) ?? "trae-cn",
                    inputTokens: input, outputTokens: output,
                    cacheCreationTokens: 0, cacheReadTokens: 0))
                return
            }
        }
        for (_, v) in obj {
            if let nested = v as? [String: Any] { extractTokens(obj: nested, records: &records, source: source) }
            if let arr = v as? [[String: Any]] {
                for item in arr { extractTokens(obj: item, records: &records, source: source) }
            }
        }
    }
}
