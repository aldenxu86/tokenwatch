import Foundation

// ============================================================
// GenericJSONLScanner —— 用户自定义 Agent(通用解析器)
// 支持三种 JSONL 变体,自动尝试:
//   1. nested:{"message":{"usage":{...}}} (Anthropic 标准)
//   2. event:{"event_msg":"token_count","last_token_usage":{...}} (Codex)
//   3. flat:{"usage":{...}} (OpenAI 兼容)
// ============================================================
struct GenericJSONLScanner: AgentScanner {
    let name: String
    let description: String
    let searchPaths: [String]
    var dataFormat: AgentDataFormat

    /// 缺省占位(Registry 默认列表用,isInstalled=false 永不扫描)
    init() {
        self.name = "自定义"
        self.description = "用户自行添加的 Agent"
        self.searchPaths = []
        self.dataFormat = .jsonlNested
    }

    /// 预置:用已知 Agent 的默认路径 + 格式
    init(customName: String, customPaths: [String], format: AgentDataFormat = .jsonlNested) {
        self.name = customName
        self.description = "自定义 Agent"
        self.searchPaths = customPaths
        self.dataFormat = format
    }

    /// 自定义 id(覆盖协议默认的类名规则)
    var id: String {
        "custom-" + name.lowercased().replacingOccurrences(of: " ", with: "-")
    }

    func parse(file: URL) async throws -> [UsageRecord] {
        let content = try String(contentsOf: file, encoding: .utf8)
        switch dataFormat {
        case .jsonlNested, .jsonlFlat:
            let sessionID = file.deletingPathExtension().lastPathComponent
            return UsageParser.parseAll(content, sessionID: sessionID, source: id)
        case .jsonlEvent:
            return try await parseEventStyle(content, file: file)
        case .genericJSON:
            return try await parseGenericJSON(file)
        default:
            return []
        }
    }

    private func parseEventStyle(_ content: String, file: URL) async throws -> [UsageRecord] {
        let sessionID = file.deletingPathExtension().lastPathComponent
        var records: [UsageRecord] = []
        for line in content.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty, let data = trimmed.data(using: .utf8),
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            else { continue }
            let usage = obj["last_token_usage"] as? [String: Any]
                ?? obj["total_token_usage"] as? [String: Any]
                ?? obj["usage"] as? [String: Any]
            guard let u = usage else { continue }
            let input = (u["input_tokens"] as? NSNumber)?.intValue ?? 0
            let output = (u["output_tokens"] as? NSNumber)?.intValue ?? 0
            guard input > 0 || output > 0 else { continue }
            let model = (obj["model"] as? String) ?? "unknown"
            var date = Date()
            if let ts = obj["timestamp"] as? NSNumber {
                var v = ts.doubleValue; if v > 1e12 { v /= 1000 }
                date = Date(timeIntervalSince1970: v)
            } else if let ts = obj["timestamp"] as? String {
                let f = ISO8601DateFormatter()
                f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                date = f.date(from: ts) ?? Date()
            }
            let rid = "\(Int(date.timeIntervalSince1970))-\(input)-\(output)"
            records.append(UsageRecord(
                id: rid, sessionID: sessionID, source: id,
                timestamp: date, model: model,
                inputTokens: input, outputTokens: output,
                cacheCreationTokens: (u["cache_creation_input_tokens"] as? NSNumber)?.intValue ?? 0,
                cacheReadTokens: (u["cache_read_input_tokens"] as? NSNumber)?.intValue ?? 0))
        }
        return records
    }

    private func parseGenericJSON(_ url: URL) async throws -> [UsageRecord] {
        let data = try Data(contentsOf: url)
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [] }
        let usage = (obj["data"] as? [String: Any])?["usage"] as? [String: Any]
            ?? obj["usage"] as? [String: Any]
        guard let u = usage else { return [] }
        let input = (u["input_tokens"] as? NSNumber)?.intValue ?? 0
        let output = (u["output_tokens"] as? NSNumber)?.intValue ?? 0
        guard input > 0 || output > 0 else { return [] }
        let model = (obj["model"] as? String) ?? "unknown"
        let rid = "gen-\(Int(Date().timeIntervalSince1970))-\(input)-\(output)"
        return [UsageRecord(
            id: rid, sessionID: "generic", source: id,
            timestamp: Date(), model: model,
            inputTokens: input, outputTokens: output,
            cacheCreationTokens: 0, cacheReadTokens: 0)]
    }
}
