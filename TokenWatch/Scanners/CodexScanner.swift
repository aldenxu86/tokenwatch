import Foundation

// ============================================================
// Codex CLI Scanner —— ~/.codex/sessions/YYYY/MM/DD/rollout-*.jsonl
// 数据格式:JSONL,event_msg:"token_count",last_token_usage 含
//   input/output/cached_input/reasoning_output_tokens
// ============================================================
struct CodexScanner: AgentScanner {
    let name = "Codex CLI"
    let description = "OpenAI Codex CLI"
    let dataFormat: AgentDataFormat = .jsonlEvent

    var searchPaths: [String] {
        ["~/.codex/sessions/"]
    }

    func parse(file: URL) async throws -> [UsageRecord] {
        let content = try String(contentsOf: file, encoding: .utf8)
        let sessionID = file.deletingPathExtension().lastPathComponent
            .replacingOccurrences(of: "rollout-", with: "")

        // Codex JSONL:每行一条事件,含 event_msg:token_count
        var records: [UsageRecord] = []
        for line in content.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty, let data = trimmed.data(using: .utf8),
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            else { continue }

            // Codex: type=event_msg, payload.type=token_count
            // token 数据嵌套在 payload.info.last_token_usage 内
            let eventType = obj["type"] as? String
            guard eventType == "event_msg" else { continue }
            let payload = obj["payload"] as? [String: Any]
            guard payload?["type"] as? String == "token_count" else { continue }
            let info = payload?["info"] as? [String: Any]
            let usage = info?["last_token_usage"] as? [String: Any]
                ?? info?["total_token_usage"] as? [String: Any]
                ?? obj["last_token_usage"] as? [String: Any]
                ?? obj["total_token_usage"] as? [String: Any]
            guard let u = usage else { continue }

            let input = (u["input_tokens"] as? Int64).map(Int.init) ?? 0
            let output = (u["output_tokens"] as? Int64).map(Int.init)
                ?? (u["reasoning_output_tokens"] as? Int64).map(Int.init) ?? 0
            guard input > 0 || output > 0 else { continue }

            let cached = (u["cached_input_tokens"] as? Int64).map(Int.init) ?? 0
            let model = (obj["model"] as? String) ?? "codex"

            // 时间戳
            var date = Date()
            if let meta = obj["__meta"] as? [String: Any],
               let ts = meta["timestamp"] as? String {
                date = parseISO8601(ts) ?? date
            } else if let ts = obj["timestamp"] as? String {
                date = parseISO8601(ts) ?? date
            } else if let ts = obj["timestamp"] as? NSNumber {
                var v = ts.doubleValue
                if v > 1e12 { v /= 1000 }
                date = Date(timeIntervalSince1970: v)
            }

            let recordID = (obj["id"] as? String) ?? "\(Int(date.timeIntervalSince1970))-\(input)-\(output)"
            records.append(UsageRecord(
                id: recordID, sessionID: sessionID, source: "codex",
                timestamp: date, model: model,
                inputTokens: input, outputTokens: output,
                cacheCreationTokens: max(0, input - cached),
                cacheReadTokens: cached
            ))
        }
        return records
    }

    private func parseISO8601(_ s: String) -> Date? {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f.date(from: s) ?? {
            let p = ISO8601DateFormatter()
            p.formatOptions = [.withInternetDateTime]
            return p.date(from: s)
        }()
    }
}
