import SwiftUI

// ============================================================
// Agent 监控 Tab:开关 + 自定义添加
// ============================================================
struct AgentTabView: View {
    @EnvironmentObject private var registry: ScannerRegistry
    @State private var customName = ""
    @State private var customPath = ""
    @State private var customFormat: AgentDataFormat = .jsonlNested
    @State private var addResult = ""
    @State private var refreshToggle = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("已检测的 Agent")
                    .font(.headline)

                ForEach(registry.scanners, id: \.id) { scanner in
                    HStack(spacing: 8) {
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 6) {
                                Text(scanner.name)
                                    .font(.system(.callout, weight: .medium))
                                Text(scanner.isInstalled ? "已安装" : "未安装")
                                    .font(.caption2)
                                    .foregroundStyle(scanner.isInstalled ? .green : .orange)
                                    .padding(.horizontal, 4)
                                    .background((scanner.isInstalled ? Color.green : Color.orange).opacity(0.12),
                                                in: RoundedRectangle(cornerRadius: 3))
                            }
                            Text(scanner.description)
                                .font(.caption).foregroundStyle(.secondary)
                            Text(scanner.searchPaths.joined(separator: ", "))
                                .font(.caption2).foregroundStyle(.tertiary).lineLimit(1)
                        }
                        Spacer()
                        Toggle("", isOn: binding(for: scanner.id))
                            .toggleStyle(.switch).labelsHidden()
                        if scanner.id.hasPrefix("custom-") {
                            Button("✕") {
                                registry.removeCustom(scanner.id)
                                refreshToggle.toggle()
                            }.controlSize(.small).tint(.red).frame(width: 28)
                        }
                    }.padding(.vertical, 3)
                }

                Divider()

                Text("添加自定义 Agent")
                    .font(.headline)

                HStack(spacing: 8) {
                    TextField("名称", text: $customName).frame(width: 100)
                    TextField("路径(如 ~/.myagent/logs/)", text: $customPath)
                    Picker("", selection: $customFormat) {
                        Text("JSONL嵌套").tag(AgentDataFormat.jsonlNested)
                        Text("JSONL事件").tag(AgentDataFormat.jsonlEvent)
                        Text("JSONL扁平").tag(AgentDataFormat.jsonlFlat)
                    }.frame(width: 100)
                    Button("添加") {
                        let n = customName.trimmingCharacters(in: .whitespaces)
                        let p = customPath.trimmingCharacters(in: .whitespaces)
                        guard !n.isEmpty, !p.isEmpty else {
                            addResult = "请输入名称和路径"
                            return
                        }
                        registry.addCustom(name: n, paths: [p], format: customFormat)
                        customName = ""
                        customPath = ""
                        refreshToggle.toggle()
                        addResult = "OK: \(n)"
                    }.buttonStyle(.borderedProminent).controlSize(.small)
                }.font(.system(.caption, design: .monospaced))

                if !addResult.isEmpty {
                    Text(addResult)
                        .font(.caption)
                        .foregroundStyle(addResult.hasPrefix("OK") ? .green : .orange)
                        .id(addResult)
                }

                Text("提示:添加后勾选开关即可生效,数据在下次扫描时自动纳入。")
                    .font(.caption2).foregroundStyle(.tertiary)
            }.padding(20)
        }.frame(minWidth: 580, minHeight: 380)
    }

    private func binding(for id: String) -> Binding<Bool> {
        Binding(
            get: { registry.enabledIDs.contains(id) },
            set: { registry.toggle(id, on: $0) }
        )
    }
}
