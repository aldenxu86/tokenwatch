import Foundation

// ============================================================
// CodeBuddy Scanner —— ~/.codebuddy/
// 腾讯 CodeBuddy(与 WorkBuddy 不同),数据在 usage-data/ 和 traces/
// ============================================================
struct CodeBuddyScanner: AgentScanner {
    let name = "CodeBuddy"
    let description = "腾讯 CodeBuddy AI 编程助手"
    let dataFormat: AgentDataFormat = .jsonlNested

    var searchPaths: [String] {
        [
            "~/.codebuddy/usage-data/",
            "~/.codebuddy/logs/",
            "~/.codebuddy/traces/"
        ]
    }

    func parse(file: URL) async throws -> [UsageRecord] {
        let content = try String(contentsOf: file, encoding: .utf8)

        // 尝试标准 JSONL 解析
        let sessionID = file.deletingPathExtension().lastPathComponent
        var records = UsageParser.parseAll(content, sessionID: sessionID, source: "codebuddy")

        // 如果标准解析无结果,尝试其他格式(traces JSON)
        if records.isEmpty && file.pathExtension == "json" {
            records = try await parseTraces(file)
        }

        return records
    }

    private func parseTraces(_ url: URL) async throws -> [UsageRecord] {
        let data = try Data(contentsOf: url)
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return [] }

        // traces 格式:可能含 usage 字段
        let usage = obj["usage"] as? [String: Any]
            ?? obj["token_usage"] as? [String: Any]
            ?? obj["tokens"] as? [String: Any]
        guard let u = usage else { return [] }

        let input = (u["input_tokens"] as? NSNumber)?.intValue
            ?? (u["input"] as? NSNumber)?.intValue ?? 0
        let output = (u["output_tokens"] as? NSNumber)?.intValue
            ?? (u["output"] as? NSNumber)?.intValue ?? 0
        guard input > 0 || output > 0 else { return [] }

        let model = (obj["model"] as? String) ?? "codebuddy"
        var date = Date()
        if let ts = obj["timestamp"] as? String {
            let f = ISO8601DateFormatter()
            f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            date = f.date(from: ts) ?? Date()
        }
        let id = "cb-\(Int(date.timeIntervalSince1970))-\(input)-\(output)"

        return [UsageRecord(
            id: id, sessionID: "codebuddy", source: "codebuddy",
            timestamp: date, model: model,
            inputTokens: input, outputTokens: output,
            cacheCreationTokens: 0,
            cacheReadTokens: (u["cache_read_input_tokens"] as? NSNumber)?.intValue ?? 0
        )]
    }
}
