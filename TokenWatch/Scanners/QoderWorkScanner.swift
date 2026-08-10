import Foundation

// ============================================================
// QoderWork CN Scanner —— 阿里通义灵码(国内版)
// 数据目录: ~/qoderwork/
// 注意:QoderWork 按 Credits 计费,无本地 token 日志
//       本 Scanner 仅做路径检测,有数据则尝试提取
// ============================================================
struct QoderWorkCNScanner: AgentScanner {
    var id: String { "qoderwork-cn" }
    let name = "QoderWork CN"
    let description = "阿里通义灵码(国内版)"
    let dataFormat: AgentDataFormat = .genericJSON

    var searchPaths: [String] {
        ["~/qoderwork/awareness/main/"]
    }

    func parse(file: URL) async throws -> [UsageRecord] {
        // QoderWork 无本地 token 日志,仅占位
        // 后续如发现可读数据源再补充解析逻辑
        return []
    }
}
