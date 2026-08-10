import SwiftUI

// ============================================================
// 设置:Agent 管理 / API 余额 / 模型价格 三个 Tab
// ============================================================
struct SettingsView: View {
    @EnvironmentObject private var store: UsageStore
    @EnvironmentObject private var registry: ScannerRegistry
    @State private var selectedTab = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            AgentTabView()
                .environmentObject(registry)
                .tabItem { Label("Agent 监控", systemImage: "cpu") }.tag(0)
            APITabView()
                .tabItem { Label("API 余额", systemImage: "creditcard") }.tag(1)
            PricingTabView()
                .environmentObject(store)
                .tabItem { Label("模型价格", systemImage: "dollarsign.circle") }.tag(2)
        }
        .frame(minWidth: 600, minHeight: 440)
        .padding(.top, 8)
    }
}

// MARK: - API 余额 Tab

struct APITabView: View {
    @State private var apiKeys: [String: String] = [:]
    @State private var balanceURLs: [String: String] = [:]
    @State private var savedKeys: Set<String> = []
    @State private var savedURLs: Set<String> = []

    private let providers: [(id: String, name: String)] = [
        ("deepseek", "DeepSeek"), ("minimax", "MiniMax"),
        ("zhipu", "智谱"), ("siliconflow", "硅基流动"),
        ("qwen", "千问")
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("平台 API Key(余额查询用,存 Keychain)")
                    .font(.headline)
                Text("填写后 TokenWatch 自动显示各平台余额/额度。千问无官方余额 API,请在下方填自定义接口 URL。")
                    .font(.caption).foregroundStyle(.secondary)

                ForEach(providers, id: \.id) { p in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 8) {
                            Text(p.name).font(.system(.caption, design: .monospaced))
                                .frame(width: 84, alignment: .leading)
                            SecureField("API Key", text: keyBinding(p.id))
                                .textFieldStyle(.roundedBorder)
                                .font(.system(.caption, design: .monospaced))
                            Button(configured(p.id) ? "已保存" : "保存") { saveKey(p.id) }
                                .disabled((apiKeys[p.id] ?? "").isEmpty).controlSize(.small)
                        }
                        HStack(spacing: 8) {
                            Text("余额接口").font(.caption2).foregroundStyle(.secondary)
                                .frame(width: 84, alignment: .leading)
                            TextField("https://… 可选", text: balanceURLBinding(p.id))
                                .textFieldStyle(.roundedBorder)
                                .font(.system(.caption, design: .monospaced))
                            Button("保存") { saveBalanceURL(p.id) }
                                .disabled((balanceURLs[p.id] ?? "").isEmpty).controlSize(.small)
                        }
                    }.padding(.vertical, 4)
                }
            }.padding(20)
        }
        .onAppear {
            apiKeys = Dictionary(uniqueKeysWithValues: providers.compactMap { p in
                BalanceFetcher.keychainKeys[p.id].flatMap { kc in
                    KeychainStore.get(kc).map { (p.id, $0) }
                }
            })
            balanceURLs = Dictionary(uniqueKeysWithValues: providers.compactMap { p in
                UserDefaults.standard.string(forKey: BalanceFetcher.customBalanceURLKey(p.id))
                    .map { (p.id, $0) }
            })
        }
    }

    private func configured(_ p: String) -> Bool {
        savedKeys.contains(p) || BalanceFetcher.isConfigured(p)
    }
    private func keyBinding(_ p: String) -> Binding<String> {
        Binding(get: { apiKeys[p] ?? "" }, set: { apiKeys[p] = $0 })
    }
    private func balanceURLBinding(_ p: String) -> Binding<String> {
        Binding(get: { balanceURLs[p] ?? "" }, set: { balanceURLs[p] = $0 })
    }
    private func saveKey(_ p: String) {
        guard let v = apiKeys[p], !v.isEmpty else { return }
        if let kc = BalanceFetcher.keychainKeys[p] { KeychainStore.set(v, forKey: kc) }
        savedKeys.insert(p)
    }
    private func saveBalanceURL(_ p: String) {
        guard let v = balanceURLs[p], !v.isEmpty else { return }
        UserDefaults.standard.set(v, forKey: BalanceFetcher.customBalanceURLKey(p))
        savedURLs.insert(p)
    }
}

// MARK: - 模型价格 Tab

struct PricingTabView: View {
    @EnvironmentObject private var store: UsageStore
    @State private var prices: [String: ModelPricing] = [:]
    @State private var saved = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("模型单价(每百万 token)")
                    .font(.headline)
                VStack(spacing: 0) {
                    HStack(spacing: 4) {
                        Text("模型").frame(width: 140, alignment: .leading)
                        Text("货币").frame(width: 36, alignment: .center)
                        Text("输入").frame(width: 62, alignment: .trailing)
                        Text("输出").frame(width: 62, alignment: .trailing)
                        Text("缓存写").frame(width: 62, alignment: .trailing)
                        Text("缓存读").frame(width: 62, alignment: .trailing)
                    }.font(.caption).foregroundStyle(.secondary).padding(.vertical, 6)
                    Divider()
                    ForEach(sortedModels, id: \.self) { model in
                        HStack(spacing: 4) {
                            Text(model).font(.system(.caption, design: .monospaced))
                                .frame(width: 140, alignment: .leading).lineLimit(1)
                            TextField("USD", text: currencyBinding(for: model))
                                .frame(width: 36).font(.system(.caption, design: .monospaced))
                                .multilineTextAlignment(.center)
                            field(binding(for: model, keyPath: \.inputPerMillion)).frame(width: 62)
                            field(binding(for: model, keyPath: \.outputPerMillion)).frame(width: 62)
                            field(binding(for: model, keyPath: \.cacheWritePerMillion)).frame(width: 62)
                            field(binding(for: model, keyPath: \.cacheReadPerMillion)).frame(width: 62)
                        }.padding(.vertical, 2)
                        if model != sortedModels.last { Divider() }
                    }
                }
                HStack {
                    if saved { Text("已保存").font(.caption).foregroundStyle(.green) }
                    Spacer()
                    Button("重新统计") { store.reloadPricing() }
                    Button("保存价格") { save() }.buttonStyle(.borderedProminent)
                }
            }.padding(20)
        }
        .onAppear { prices = Pricing.load(); saved = false }
    }

    private var sortedModels: [String] { prices.keys.sorted() }

    private func binding(for model: String, keyPath: WritableKeyPath<ModelPricing, Double>) -> Binding<Double> {
        Binding(get: { prices[model]?[keyPath: keyPath] ?? 0 },
                set: { n in if var p = prices[model] { p[keyPath: keyPath] = n; prices[model] = p } })
    }
    private func currencyBinding(for model: String) -> Binding<String> {
        Binding(get: { prices[model]?.currency ?? "USD" },
                set: { n in if var p = prices[model] { p.currency = n; prices[model] = p } })
    }
    private func field(_ value: Binding<Double>) -> some View {
        TextField("", value: value, format: .number.precision(.fractionLength(2)))
            .textFieldStyle(.roundedBorder).font(.system(.caption, design: .monospaced))
            .multilineTextAlignment(.trailing)
    }
    private func save() { Pricing.save(prices); saved = true; store.reloadPricing() }
}
