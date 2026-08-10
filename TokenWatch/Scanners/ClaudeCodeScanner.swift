import Foundation

// ============================================================
// Claude Code Scanner —— ~/.claude/projects/**/*.jsonl
// ============================================================
struct ClaudeCodeScanner: AgentScanner {
    var id: String { "claude-code" }
    let name = "Claude Code"
    let description = "Anthropic 官方 CLI Agent"
    let dataFormat: AgentDataFormat = .jsonlNested

    var searchPaths: [String] {
        ["~/.claude/projects/"]
    }

    func parse(file: URL) async throws -> [UsageRecord] {
        let content = try String(contentsOf: file, encoding: .utf8)
        let sessionID = file.deletingPathExtension().lastPathComponent
        return UsageParser.parseAll(content, sessionID: sessionID, source: "claude-code")
    }
}
