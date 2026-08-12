import SwiftUI
import Charts

// ============================================================
// 详情窗口:汇总卡片 + 近30天柱状图 + 按模型分布
// ============================================================
struct DashboardView: View {
    @EnvironmentObject private var store: UsageStore
    @EnvironmentObject private var balances: BalanceFetcher

    private var dayBars: [DayBar] {
        store.perDay.keys.sorted().map {
            DayBar(date: $0,
                   tokens: store.perDay[$0]?.totalTokens ?? 0,
                   cost: store.perDay[$0]?.totalCost ?? 0)
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // 各平台余额
                balanceSection
                // 汇总卡片(金额统一折算为 CNY,按实时汇率)
                HStack(spacing: 12) {
                    SummaryCard(title: "今日", tokens: store.today.totalTokens,
                                cost: store.today.cost(in: "CNY", usdRate: store.usdToCNY),
                                requests: store.today.requestCount, currency: "CNY")
                    SummaryCard(title: "近7日", tokens: store.week.totalTokens,
                                cost: store.week.cost(in: "CNY", usdRate: store.usdToCNY),
                                requests: store.week.requestCount, currency: "CNY")
                    SummaryCard(title: "累计", tokens: store.allTime.totalTokens,
                                cost: store.allTime.cost(in: "CNY", usdRate: store.usdToCNY),
                                requests: store.allTime.requestCount, currency: "CNY")
                }

                // 近30天趋势
                VStack(alignment: .leading, spacing: 6) {
                    Text("近30天用量")
                        .font(.headline)
                    Chart(dayBars) { bar in
                        BarMark(
                            x: .value("日期", bar.date, unit: .day),
                            y: .value("tokens", bar.tokens)
                        )
                        .foregroundStyle(.blue.gradient)
                    }
                    .chartXAxis {
                        AxisMarks(values: .stride(by: .day, count: 5)) { _ in
                            AxisGridLine().foregroundStyle(.quaternary)
                            AxisValueLabel(format: .dateTime.month().day())
                        }
                    }
                    .frame(height: 180)
                }

                // 按 Agent 来源
                if !store.perSource.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("按 Agent 来源")
                            .font(.headline)
                        ForEach(store.perSource, id: \.source) { item in
                            HStack {
                                Text(item.name)
                                    .font(.system(.callout, design: .monospaced))
                                    .frame(width: 120, alignment: .leading)
                                ProgressView(value: sourceFraction(item.summary.totalTokens))
                                    .tint(.green)
                                Text(Format.tokens(item.summary.totalTokens))
                                    .font(.system(.caption, design: .monospaced))
                                    .frame(width: 64, alignment: .trailing)
                                Text("\(item.summary.requestCount) 次")
                                    .font(.system(.caption, design: .monospaced))
                                    .foregroundStyle(.secondary)
                                    .frame(width: 50, alignment: .trailing)
                            }
                        }
                    }
                }

                // 按模型
                VStack(alignment: .leading, spacing: 6) {
                    Text("按模型分布(累计)")
                        .font(.headline)
                    if store.perModel.isEmpty {
                        Text("暂无数据 —— 有会话活动后自动出现")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(store.perModel, id: \.model) { item in
                            HStack {
                                Text(item.model)
                                    .font(.system(.callout, design: .monospaced))
                                    .frame(width: 160, alignment: .leading)
                                    .lineLimit(1)
                                ProgressView(value: fraction(item.summary.totalTokens))
                                    .tint(.blue)
                                Text(Format.tokens(item.summary.totalTokens))
                                    .font(.system(.caption, design: .monospaced))
                                    .frame(width: 60, alignment: .trailing)
                                Text(Format.cost(item.summary.totalCost,
                                                 currency: modelCurrency(item.model)))
                                    .font(.system(.caption, design: .monospaced))
                                    .foregroundStyle(.secondary)
                                    .frame(width: 64, alignment: .trailing)
                            }
                        }
                    }
                }
            }
            .padding(20)
        }
    }

    /// 查某模型的货币
    private func modelCurrency(_ model: String) -> String {
        Pricing.price(for: model, table: Pricing.load()).currency
    }

    // MARK: 各平台余额

    private var balanceSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("各平台余额")
                    .font(.headline)
                Spacer()
                if balances.isFetching {
                    ProgressView().controlSize(.small)
                }
                Button("刷新") { Task { await balances.refreshAll() } }
                    .controlSize(.small)
            }
            HStack(spacing: 10) {
                ForEach(balances.balances) { b in
                    VStack(alignment: .leading, spacing: 3) {
                        Text(b.displayName)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(b.summary)
                            .font(.callout.weight(.semibold).monospaced())
                            .lineLimit(1)
                        Text(b.detail)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                            .lineLimit(2)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
                    .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 8))
                }
            }
            if let err = balances.lastError {
                Text(err)
                    .font(.caption2)
                    .foregroundStyle(.orange)
            }
        }
    }

    private func sourceFraction(_ tokens: Int) -> Double {
        let max = store.perSource.first?.summary.totalTokens ?? 1
        return max > 0 ? Double(tokens) / Double(max) : 0
    }

    private func fraction(_ tokens: Int) -> Double {
        let max = store.perModel.first?.summary.totalTokens ?? 1
        return max > 0 ? Double(tokens) / Double(max) : 0
    }
}

struct DayBar: Identifiable {
    let date: Date
    let tokens: Int
    let cost: Double
    var id: Date { date }
}

struct SummaryCard: View {
    let title: String
    let tokens: Int
    let cost: Double
    let requests: Int
    let currency: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(Format.tokens(tokens))
                .font(.title2.weight(.semibold).monospaced())
            Text("\(Format.cost(cost, currency: currency)) · \(requests) 请求")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 10))
    }
}
