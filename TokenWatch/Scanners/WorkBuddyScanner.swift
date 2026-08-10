import Foundation

// ============================================================
// WorkBuddy Scanner
// 数据源: ~/.workbuddy/traces/*/trace_*.json(每调用一条)
//        + ~/.workbuddy/workbuddy.db(session_usage.credit_json)
// ============================================================
struct WorkBuddyScanner: AgentScanner {
    var id: String { "workbuddy" }
    let name = "WorkBuddy"
    let description = "腾讯 WorkBuddy AI 编程助手"
    let dataFormat: AgentDataFormat = .genericJSON

    var searchPaths: [String] {
        ["~/.workbuddy/traces/"]
    }

    func parse(file: URL) async throws -> [UsageRecord] {
        guard file.pathExtension == "json" else { return [] }
        let data = try Data(contentsOf: file)

        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return [] }

        let trace = obj["trace"] as? [String: Any] ?? obj
        let totalTokens = (trace["totalTokens"] as? NSNumber)?.intValue ?? 0
        guard totalTokens > 0 else { return [] }

        // spans 数组:每个子调用含 token 信息
        let spans = obj["spans"] as? [[String: Any]] ?? []
        var records: [UsageRecord] = []

        for span in spans {
            let spanTokens = (span["totalTokens"] as? NSNumber)?.intValue ?? 0
            let usage = span["usage"] as? [String: Any]
            let input = (usage?["input_tokens"] as? NSNumber)?.intValue
                ?? (span["inputTokens"] as? NSNumber)?.intValue ?? 0
            let output = (usage?["output_tokens"] as? NSNumber)?.intValue
                ?? (span["outputTokens"] as? NSNumber)?.intValue ?? 0
            guard input > 0 || output > 0 else { continue }

            let model = (span["model"] as? String) ?? "workbuddy"
            let startedAt = span["startedAt"] as? String ?? trace["startedAt"] as? String
            let date = parseISO8601(startedAt) ?? Date()
            let rid = "wb-\(Int(date.timeIntervalSince1970))-\(input)-\(output)"
            records.append(UsageRecord(
                id: rid, sessionID: "workbuddy", source: "workbuddy",
                timestamp: date, model: model,
                inputTokens: input, outputTokens: output,
                cacheCreationTokens: (usage?["cache_creation_input_tokens"] as? NSNumber)?.intValue ?? 0,
                cacheReadTokens: (usage?["cache_read_input_tokens"] as? NSNumber)?.intValue ?? 0))
        }

        // 如果 spans 为空但有 trace 级别的 totalTokens,创建一条聚合记录
        if records.isEmpty && totalTokens > 0 {
            let startedAt = trace["startedAt"] as? String
            let date = parseISO8601(startedAt) ?? Date()
            let rid = "wb-\(Int(date.timeIntervalSince1970))-\(totalTokens)-0"
            records.append(UsageRecord(
                id: rid, sessionID: "workbuddy", source: "workbuddy",
                timestamp: date, model: "workbuddy",
                inputTokens: totalTokens / 2, outputTokens: totalTokens / 2,
                cacheCreationTokens: 0, cacheReadTokens: 0))
        }

        return records
    }

    private func parseISO8601(_ s: String?) -> Date? {
        guard let s else { return nil }
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f.date(from: s) ?? {
            let p = ISO8601DateFormatter()
            p.formatOptions = [.withInternetDateTime]
            return p.date(from: s)
        }()
    }
}
