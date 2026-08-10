import SwiftUI

@main
struct TokenWatchApp: App {
    @StateObject private var registry: ScannerRegistry
    @StateObject private var balances = BalanceFetcher()
    @StateObject private var store: UsageStore

    init() {
        let reg = ScannerRegistry()
        _registry = StateObject(wrappedValue: reg)
        _store = StateObject(wrappedValue: UsageStore(registry: reg))
    }

    var body: some Scene {
        // 菜单栏常驻
        MenuBarExtra {
            MenuBarView()
                .environmentObject(store)
                .environmentObject(balances)
                .task {
                    await balances.refreshAll()
                    // 每小时自动刷新余额
                    while !Task.isCancelled {
                        try? await Task.sleep(nanoseconds: 3600_000_000_000)
                        await balances.refreshAll()
                    }
                }
        } label: {
            MenuBarLabel(store: store)
        }
        .menuBarExtraStyle(.window)

        // 详情窗口
        WindowGroup("用量详情", id: "dashboard") {
            DashboardView()
                .environmentObject(store)
                .environmentObject(balances)
                .frame(minWidth: 560, minHeight: 420)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 640, height: 480)

        // 设置(用 WindowGroup 替代 Settings —— 菜单栏 App 更可靠)
        WindowGroup("设置", id: "settings") {
            SettingsView()
                .environmentObject(store)
                .environmentObject(balances)
                .environmentObject(registry)
                .frame(minWidth: 600, minHeight: 440)
        }
        .windowStyle(.titleBar)
        .defaultSize(width: 620, height: 500)
    }
}

/// 菜单栏图标:今日 tokens 简写(如 "12.3k")
struct MenuBarLabel: View {
    @ObservedObject var store: UsageStore

    var body: some View {
        Text("📦 \(Format.tokens(store.today.totalTokens))")
            .font(.system(size: 11, weight: .medium, design: .monospaced))
            .help("TokenWatch:今日 \(Format.tokens(store.today.totalTokens)) tokens")
            .task {
                store.start()
            }
    }
}
