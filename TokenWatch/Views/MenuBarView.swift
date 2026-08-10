import SwiftUI

// ============================================================
// 菜单栏下拉面板:当前会话 / 今日 / 7日 / 按模型 / 操作按钮
// ============================================================
struct MenuBarView: View {
    @EnvironmentObject private var store: UsageStore
    @EnvironmentObject private var balances: BalanceFetcher
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // ---- 当前会话(实时)----
            if !store.currentSessionID.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("当前会话 · 实时")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    HStack {
                        summaryRow(store.currentSession, emphasized: true)
                        Spacer()
                        Text("\(store.currentSession.requestCount) 次请求")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
                .padding(10)
                .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
            }

            // ---- 汇总 ----
            VStack(alignment: .leading, spacing: 6) {
                summaryRow(store.today, title: "今日")
                summaryRow(store.week, title: "近7日")
                summaryRow(store.allTime, title: "累计")
            }

            // ---- 按模型 ----
            if !store.perModel.isEmpty {
                Divider()
                ForEach(store.perModel.prefix(5), id: \.model) { item in
                    HStack {
                        Text(item.model)
                            .font(.system(.caption, design: .monospaced))
                            .lineLimit(1)
                        Spacer()
                        Text(Format.tokens(item.summary.totalTokens))
                            .font(.system(.caption, design: .monospaced))
                        Text(Format.cost(item.summary.totalCost,
                                         currency: Pricing.price(for: item.model, table: Pricing.load()).currency))
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Divider()

            // ---- 操作 ----
            HStack {
                Button("详情") { toggleDashboard() }
                Button("刷新") { store.refreshNow() }
                Spacer()
                if store.enabledAgentCount > 0 {
                    Text("\(store.enabledAgentCount) Agent")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                if let at = store.lastScanAt {
                    Text(at, style: .time)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                Button("设置…") { openSettings() }
            }
            .controlSize(.small)

            HStack {
                Spacer()
                Button("退出 TokenWatch") { NSApp.terminate(nil) }
                    .controlSize(.small)
            }
        }
        .padding(12)
        .frame(width: 320)
    }

    private func summaryRow(_ s: UsageSummary, title: String? = nil, emphasized: Bool = false) -> some View {
        HStack(spacing: 8) {
            if let title {
                Text(title)
                    .font(.system(.caption, weight: .medium))
                    .frame(width: 44, alignment: .leading)
                    .foregroundStyle(.secondary)
            }
            Text("⬆ \(Format.tokens(s.totalInput))")
            Text("⬇ \(Format.tokens(s.totalOutput))")
                .foregroundStyle(.secondary)
            if s.totalCacheRead > 0 {
                Text("📦 \(Format.tokens(s.totalCacheRead))")
                    .foregroundStyle(.tertiary)
            }
            Spacer()
            Text(Format.cost(s.totalCost, currency: dominantCurrency))
                .font(.system(.caption, design: .monospaced, weight: emphasized ? .semibold : .regular))
                .foregroundStyle(emphasized ? .primary : .secondary)
        }
        .font(.system(.caption, design: .monospaced))
    }

    private var dominantCurrency: String {
        // 用量最大的 Agent 来源决定货币
        if let top = store.perSource.first {
            return Pricing.currencyForAgent(top.source)
        }
        if let top = store.perModel.first?.model {
            return Pricing.price(for: top, table: Pricing.load()).currency
        }
        return "CNY"
    }

    private func toggleDashboard() {
        // 详情窗口:已打开则关,未打开则打开
        if let win = NSApp.windows.first(where: { $0.title == "用量详情" }) {
            win.close()
        } else {
            openWindow(id: "dashboard")
        }
    }

    private func openSettings() {
        if let win = NSApp.windows.first(where: { $0.title == "设置" }) {
            win.makeKeyAndOrderFront(nil)
        } else {
            openWindow(id: "settings")
        }
    }
}
