import Foundation

// ============================================================
// 通用 JSONL 解析器(Claude Code、代理日志、自定义 Agent 共用)
// ============================================================
struct UsageParser: Sendable {

    /// 解析文件全部内容,返回所有含 usage 的记录(跨行安全)
    static func parseAll(_ content: String, sessionID: String, source: String = "unknown") -> [UsageRecord] {
        var records: [UsageRecord] = []
        var buffer = String.UnicodeScalarView()
        var depth = 0
        var inString = false
        var escaped = false
        var inRecord = false

        for scalar in content.unicodeScalars {
            if !inRecord {
                // 跳过记录外的空白,遇到 '{' 开始一条记录
                if scalar == "{" {
                    inRecord = true
                    depth = 1
                    buffer.removeAll(keepingCapacity: true)
                    buffer.append(scalar)
                }
                continue
            }

            buffer.append(scalar)

            if inString {
                if escaped {
                    escaped = false
                } else if scalar == "\\" {
                    escaped = true
                } else if scalar == "\"" {
                    inString = false
                }
            } else {
                switch scalar {
                case "\"": inString = true
                case "{": depth += 1
                case "}":
                    depth -= 1
                    if depth == 0 {
                        // 一条完整记录
                        if let rec = parseLine(String(buffer), sessionID: sessionID, source: source) {
                            records.append(rec)
                        }
                        inRecord = false
                    }
                default: break
                }
            }
        }
        return records
    }

    /// 解析单条完整 JSON 记录;无 usage 返回 nil
    static func parseLine(_ record: String, sessionID: String, source: String = "unknown") -> UsageRecord? {
        guard let data = record.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let message = obj["message"] as? [String: Any]
        else { return nil }

        // usage 嵌套在 message 内(顶层没有)
        guard let usage = message["usage"] as? [String: Any],
              let input = intValue(usage["input_tokens"]),
              let output = intValue(usage["output_tokens"])
        else { return nil }

        let model = (message["model"] as? String) ?? "unknown"

        // timestamp 可能是 epoch 数字(秒/毫秒)或 ISO8601 字符串(如 "2026-08-10T09:01:09.900Z")
        var date: Date?
        if let num = (obj["timestamp"] as? NSNumber)?.doubleValue {
            var v = num
            if v > 1e12 { v /= 1000 }  // 毫秒时间戳 → 秒
            date = Date(timeIntervalSince1970: v)
        } else if let str = obj["timestamp"] as? String {
            date = parseISO8601(str)
        }

        // id:代理日志自带唯一 id;transcript 无 id 时回落为时间戳+tokens 组合
        let recordID = (obj["id"] as? String)
            ?? "\(Int((date ?? Date()).timeIntervalSince1970))-\(input)-\(output)"

        return UsageRecord(
            id: recordID,
            sessionID: sessionID,
            source: source,
            timestamp: date ?? Date(),
            model: model,
            inputTokens: input,
            outputTokens: output,
            cacheCreationTokens: intValue(usage["cache_creation_input_tokens"]) ?? 0,
            cacheReadTokens: intValue(usage["cache_read_input_tokens"]) ?? 0
        )
    }

    private static func intValue(_ value: Any?) -> Int? {
        (value as? NSNumber)?.intValue
    }

    /// 解析 ISO8601 时间戳(兼容带/不带小数秒)。formatter 按调用创建,
    /// 避免 static 存储的并发安全问题;解析发生在后台 utility 线程,量小无感知
    private static func parseISO8601(_ s: String) -> Date? {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = fractional.date(from: s) { return d }
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        return plain.date(from: s)
    }
}
