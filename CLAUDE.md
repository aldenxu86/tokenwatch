# TokenWatch

macOS 菜单栏 SwiftUI 应用,实时监控所有 AI Coding Agent 的 Token 用量和平台余额。

## 项目结构

```
tokenwatch/
├── CLAUDE.md               # 本文件 —— 新会话入口
├── project.yml             # xcodegen 规格(新增 Swift 文件后必须运行 xcodegen generate)
├── build-release.sh        # 打包 DMG 脚本
├── README.md               # 对外说明
├── proxy/                  # Node.js 零依赖本地代理
│   ├── server.js           # 代理服务(port 8787,记录非 Agent API 调用)
│   └── config.json         # 路由/平台配置(apiKey 用 ${ENV} 占位,不落盘)
└── TokenWatch/             # SwiftUI App
    ├── TokenWatchApp.swift      # @main 入口
    ├── AgentScanner.swift       # 协议 + discover/isInstalled/parse
    ├── ScannerRegistry.swift    # Scanner 注册/启停/自定义持久化
    ├── UsageStore.swift         # 数据引擎(ScannerRegistry 驱动)
    ├── UsageParser.swift        # JSONL 跨行解析(brace-balance 流式)
    ├── BalanceFetcher.swift     # 平台余额轮询(Keychain + 自定义 URL)
    ├── ExchangeRate.swift       # USD→CNY 汇率(er-api/frankfurter 双源 + 缓存兜底)
    ├── Pricing.swift            # 模型价格表(USD/CNY 货币区分)
    ├── KeychainStore.swift      # Keychain 封装(API Key 安全存储)
    ├── Models.swift             # UsageRecord/UsageSummary/ModelPricing/Format
    ├── Views/
    │   ├── MenuBarView.swift    # 菜单栏下拉面板
    │   ├── DashboardView.swift  # 详情窗口(ScrollView)
    │   ├── SettingsView.swift   # 设置(Agent/API/价格 三 Tab)
    │   └── AgentTabView.swift   # Agent 管理 Tab
    └── Scanners/               # 各 Agent 数据源实现
        ├── ClaudeCodeScanner.swift   # ~/.claude/projects/**/*.jsonl
        ├── CodexScanner.swift        # ~/.codex/sessions/ rollout JSONL
        ├── CursorScanner.swift       # state.vscdb SQLite
        ├── WorkBuddyScanner.swift    # ~/.workbuddy/traces/
        ├── CodeBuddyScanner.swift    # ~/.codebuddy/
        ├── ProxyLogScanner.swift     # ~/.tokenwatch/proxy/
        ├── TraeScanner.swift         # Trae 国际版
        ├── TraeWorkScanner.swift     # Trae Work CN
        ├── QoderWorkScanner.swift    # QoderWork CN
        └── GenericJSONLScanner.swift # 用户自定义
```

## 架构

```
Scanner(discover→parse) → Registry(启停+注册) → UsageStore(扫描+聚合+偏移持久化) → @Published → SwiftUI Views
                                                         ↓
                                              BalanceFetcher(余额轮询) → ProviderBalance → Views
```

### 数据流

1. App 启动 → `MenuBarLabel.task` 调用 `store.start()`
2. `fullScan()` → `ScannerRegistry.fullScan()` → 遍历已启用 Scanner → discover() + parse() → UsageRecord 列表
3. `ingest(parsed, isFull: true)` → 清空 accumulators → 聚合 dayAcc/modelAcc/sourceAcc/sessionAcc → 发布
4. 1 秒 Timer → `incrementalScan()` → 只读 24h 内修改的文件(1MB 重叠窗口)→ 增量 ingest
5. 偏移记录在 `scanOffsets.v2`(UserDefaults),重启后可续扫

### 关键数据格式

- Claude Code transcript: `{"message":{"usage":{"input_tokens":N,"output_tokens":N}},"model":"..."}` ,timestamp 是 ISO8601 字符串
- Codex rollout: `{"type":"event_msg","payload":{"type":"token_count","info":{"last_token_usage":{...}}}}`
- Proxy log: `{"id":"<uuid>","timestamp":"<ISO8601>","message":{"model":"...","usage":{...}}}`
- usage 字段: Anthropic 标准 `input_tokens/output_tokens/cache_creation_input_tokens/cache_read_input_tokens`
- OpenAI 兼容: `prompt_tokens/completion_tokens` → 代理侧 normalizeUsage 转换

## 开发命令

```bash
# 新增 Swift 文件后必须
xcodegen generate

# 构建(未签名)
xcodebuild -project TokenWatch.xcodeproj -scheme TokenWatch -configuration Debug build \
  CODE_SIGN_IDENTITY=- CODE_SIGNING_ALLOWED=NO -derivedDataPath build

# 运行
open build/Build/Products/Debug/TokenWatch.app

# 停止旧实例
pkill -x TokenWatch

# 打包 DMG
./build-release.sh

# 发布
gh release create v<version> --title "TokenWatch v<version>" --notes "..." ./dist/TokenWatch-<version>.dmg
```

## Agent 安装检测

| Agent | 本机(macOS) | 检测路径 |
|-------|-----------|----------|
| Claude Code | ✅ | `~/.claude/projects/` |
| Codex | ✅ | `~/.codex/sessions/` |
| WorkBuddy | ✅ | `~/.workbuddy/traces/` |
| Cursor | ❌ | `~/Library/Application Support/Cursor/` |
| CodeBuddy | ❌ | `~/.codebuddy/` |
| Trae 国际版 | ❌ | `~/Library/Application Support/Trae/` |
| Trae CN | ❌ | `~/Library/Application Support/Trae CN/` |
| Trae Work CN | ❌ | 同 Trae CN 路径 |
| QoderWork CN | ❌ | `~/qoderwork/` |
| Proxy | ✅ | `~/.tokenwatch/proxy/` |

## 注意事项

- SwiftUI `Settings` scene 与 `@EnvironmentObject` 不兼容 → 改用 `WindowGroup(id:"settings")`
- `MenuBarExtra` 不支持 `ScrollView`(会导致窗口压缩成一条线)
- `@StateObject` 不能在 `init()` 中给默认值 + 手动赋值(冲突),只能选一种
- `ModelPricing` 加了 `currency` 字段后,旧的 UserDefaults 数据会解码失败 → 需清旧 key
- Agent scanner `id` 必须显式声明,不能用协议默认的类名推导(大小写/连字符不匹配)
- FileManager enumerator 对隐藏目录(`.claude/`)无特殊处理,正常枚举
