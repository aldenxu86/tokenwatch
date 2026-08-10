import Foundation

// ============================================================
// Trae Work CN Scanner
// Trae 国内版 SOLO 模式独立产品,数据目录同 Trae CN
// 会话数据加密(SQLCipher4),token 不可直接读,做路径检测
// ============================================================
struct TraeWorkCNScanner: AgentScanner {
    var id: String { "traework-cn" }
    let name = "Trae Work CN"
    let description = "字节跳动 Trae Work(国内 SOLO 模式)"
    let dataFormat: AgentDataFormat = .sqlite

    var searchPaths: [String] {
        ["~/Library/Application Support/Trae CN/User/globalStorage/state.vscdb"]
    }

    func parse(file: URL) async throws -> [UsageRecord] {
        // 主数据 SQLCipher4 加密不可读,仅尝试 vscdb 元数据
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/sqlite3")
        process.arguments = [file.path,
            "SELECT value FROM ItemTable WHERE key LIKE '%token%' LIMIT 20"]
        let pipe = Pipe()
        process.standardOutput = pipe
        try process.run()
        process.waitUntilExit()
        guard let text = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8),
              !text.isEmpty else { return [] }

        var records: [UsageRecord] = []
        for line in text.components(separatedBy: .newlines) {
            guard let data = line.data(using: .utf8),
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            else { continue }
            for key in ["usage", "token_usage"] {
                if let u = obj[key] as? [String: Any] {
                    let input = (u["input_tokens"] as? NSNumber)?.intValue ?? 0
                    let output = (u["output_tokens"] as? NSNumber)?.intValue ?? 0
                    if input > 0 || output > 0 {
                        records.append(UsageRecord(
                            id: "twc-\(Int(Date().timeIntervalSince1970))-\(input)-\(output)",
                            sessionID: "traework-cn", source: "traework-cn",
                            timestamp: Date(), model: "trae-work",
                            inputTokens: input, outputTokens: output,
                            cacheCreationTokens: 0, cacheReadTokens: 0))
                    }
                }
            }
        }
        return records
    }
}
