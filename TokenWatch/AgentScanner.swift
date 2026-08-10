import Foundation

// ============================================================
// AgentScanner 协议 —— 每个 AI Coding Agent 的数据接入点
// ============================================================

enum AgentDataFormat: String, CaseIterable, Codable, Sendable {
    case jsonlNested       // {"message":{"usage":{"input_tokens":...}}} (Claude Code 等)
    case jsonlEvent        // {"event_msg":"token_count","last_token_usage":{...}} (Codex)
    case jsonlFlat         // {"usage":{"input_tokens":...}} (usage 在顶层)
    case sqlite            // SQLite 数据库(需提供表名 + 字段映射)
    case jsonMessages      // {"messages":[{"type":"gemini","tokens":...}]} (Gemini CLI)
    case genericJSON       // JSON 文件(非 JSONL)
}

protocol AgentScanner: Sendable, Identifiable {
    var id: String { get }           // "claude-code"
    var name: String { get }         // "Claude Code"
    var description: String { get }  // 一行简介
    var dataFormat: AgentDataFormat { get }
    var searchPaths: [String] { get } // 数据文件路径(支持 ~ 展开,目录递归,*.jsonl 通配)

    func parse(file: URL) async throws -> [UsageRecord]
    var isInstalled: Bool { get }   // 自动检测路径是否存在
}

// MARK: 默认实现
extension AgentScanner {
    var id: String { String(describing: type(of: self)).replacingOccurrences(of: "Scanner", with: "").lowercased() }

    var isInstalled: Bool {
        for p in searchPaths {
            let expanded = NSString(string: p).expandingTildeInPath
            // 只检查目录本身(或文件路径的父目录)是否存在 —— 不往上追溯
            let url = URL(fileURLWithPath: expanded)
            let fm = FileManager.default
            if url.hasDirectoryPath {
                if fm.fileExists(atPath: expanded) { return true }
            } else {
                let parent = url.deletingLastPathComponent().path
                if fm.fileExists(atPath: parent) { return true }
            }
        }
        return false
    }

    /// 展开 searchPaths,发现实际存在的 jsonl 文件
    func discover() -> [URL] {
        let fm = FileManager.default
        var results: [URL] = []
        for pattern in searchPaths {
            let expanded = NSString(string: pattern).expandingTildeInPath
            let base = URL(fileURLWithPath: expanded)

            if pattern.contains("*") {
                // 通配符:枚举父目录找匹配
                let parent = base.deletingLastPathComponent()
                let glob = base.lastPathComponent
                guard let enumerator = fm.enumerator(at: parent, includingPropertiesForKeys: [.isRegularFileKey])
                else { continue }
                for case let url as URL in enumerator {
                    guard url.pathExtension == "jsonl" || url.pathExtension == "json" ||
                          url.pathExtension == "db" || url.pathExtension == "sqlite"
                    else { continue }
                    if wildcardMatch(name: url.lastPathComponent, pattern: glob) { results.append(url) }
                }
            } else if base.pathExtension == "jsonl" || base.pathExtension == "json" ||
                        base.pathExtension == "db" || base.pathExtension == "sqlite" {
                // 单文件
                if fm.fileExists(atPath: expanded) { results.append(base) }
            } else {
                // 目录:递归枚举 jsonl/json/db
                guard let enumerator = fm.enumerator(at: base, includingPropertiesForKeys: [.isRegularFileKey])
                else { continue }
                for case let url as URL in enumerator {
                    let ext = url.pathExtension
                    if ext == "jsonl" || ext == "json" || ext == "db" || ext == "sqlite" {
                        results.append(url)
                    }
                }
            }
        }
        return results
    }

    private func wildcardMatch(name: String, pattern: String) -> Bool {
        guard pattern.contains("*") else { return name == pattern }
        let parts = pattern.components(separatedBy: "*")
        var idx = name.startIndex
        for (i, part) in parts.enumerated() {
            if part.isEmpty { continue }
            guard let range = name[idx...].range(of: part) else { return false }
            if i == 0 { guard range.lowerBound == name.startIndex else { return false } }
            idx = range.upperBound
        }
        return parts.last?.isEmpty == true || idx == name.endIndex
    }
}
