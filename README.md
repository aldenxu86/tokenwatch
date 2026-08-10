# TokenWatch 📦

> macOS 菜单栏工具:实时监控所有 AI Coding Agent 的 Token 用量和平台余额

TokenWatch 是一个 macOS 原生(SwiftUI)菜单栏应用,自动扫描本地 AI 编程工具的会话记录,提供实时 Token 用量统计、费用估算和多平台余额查询。

## 功能

- **10+ Agent 自动检测** — 自动发现 Claude Code、Codex CLI、Cursor、WorkBuddy、Trae、QoderWork 等工具的本地数据
- **实时 Token 统计** — 每秒增量扫描,显示今日/近7日/累计/按模型/按 Agent 分布
- **多平台余额** — DeepSeek / MiniMax / 智谱 / 硅基流动 / 千问,填 Key 可查余额
- **费用估算** — 按模型配置单价,支持 USD/CNY 货币区分
- **本地代理(可选)** — 记录所有非 Agent 的 API 调用,自动纳入统计
- **完全自助** — 可添加自定义 Agent、自定义 API 余额接口、自定义模型价格

## 截图

菜单栏显示今日 Token 总量,下拉面板含当前会话/汇总/模型分布,详情窗口有 30 天趋势图和余额卡片。

```
📦 1.9M    ← 菜单栏图标 + 今日 tokens
```

## 安装

### 方式 1:下载 DMG

从 [Releases](https://github.com/aldenxu86/tokenwatch/releases) 下载 `TokenWatch-*.dmg`,拖入 Applications。

首次打开若提示"无法验证开发者":
- 右键 App → 点"打开"
- 或终端执行: `xattr -dr com.apple.quarantine /Applications/TokenWatch.app`

### 方式 2:Homebrew(即将支持)

```bash
brew install --cask tokenwatch
```

### 方式 3:自行构建

```bash
git clone https://github.com/aldenxu86/tokenwatch.git
cd tokenwatch
xcodegen generate
xcodebuild -project TokenWatch.xcodeproj -scheme TokenWatch \
  -configuration Release build \
  CODE_SIGN_IDENTITY=- CODE_SIGNING_ALLOWED=NO \
  -derivedDataPath build
open build/Build/Products/Release/TokenWatch.app
```

## 支持的 Agent

| Agent | 数据源 | 自动检测 |
|-------|--------|---------|
| Claude Code | `~/.claude/projects/**/*.jsonl` | ✅ |
| Codex CLI | `~/.codex/sessions/` | ✅ |
| Cursor | `state.vscdb` | ✅ |
| WorkBuddy | `~/.workbuddy/traces/` | ✅ |
| CodeBuddy | `~/.codebuddy/` | ✅ |
| Trae 国际版 | `state.vscdb` | ✅ |
| Trae 国内版 | `state.vscdb` | ✅ |
| Trae Work CN | `state.vscdb` | ✅ |
| QoderWork CN | `~/qoderwork/` | ✅ |
| 本地代理 | `~/.tokenwatch/proxy/` | ✅ |
| 自定义 | 用户自行添加路径 | 🆕 |

## 支持的 API 平台

| 平台 | 余额查询 | 说明 |
|------|---------|------|
| DeepSeek | ✅ 官方接口 | 自动识别 CNY/USD |
| MiniMax | ✅ 官方接口 | Token Plan 余额 |
| 智谱 | ⚠️ 逆向接口 | 社区逆向,可能变动 |
| 硅基流动 | ✅ 官方接口 | 充值+赠送余额 |
| 千问(Qwen) | 需自定义 URL | 无官方余额 API |
| 自定义 | ✅ 通用解析 | 填 HTTP URL 即可 |

## 本地代理(可选)

TokenWatch 内置一个零依赖 Node.js 代理(port 8787),可记录所有非 Agent 的 API 调用:

```bash
# 安装开机自启
cp proxy/com.tokenwatch.proxy.plist ~/Library/LaunchAgents/
launchctl load ~/Library/LaunchAgents/com.tokenwatch.proxy.plist

# 设置环境变量(在 ~/.zshenv 中)
export DEEPSEEK_API_KEY=sk-xxx
export SILICONFLOW_API_KEY=sk-xxx

# 使用:把 API base_url 指向代理
# http://127.0.0.1:8787/v1
```

代理会根据模型名前缀自动路由到对应平台。日志按天写入 `~/.tokenwatch/proxy/`,TokenWatch 自动读取。

## 技术架构

- **语言**: Swift 6 + SwiftUI
- **平台**: macOS 14.0+
- **核心模块**:
  - `AgentScanner` 协议 — 可插拔的 Agent 数据源
  - `ScannerRegistry` — 注册中心,管理启停
  - `UsageStore` — 扫描引擎,每秒增量,偏移持久化
  - `BalanceFetcher` — 各平台余额轮询
  - `proxy/` — Node.js 零依赖本地代理
- **安全**: API Key 存 macOS Keychain,不落盘
- **签名**: 开发阶段未签名,分发用 DMG

## 项目结构

```
TokenWatch/
├── AgentScanner.swift        # 协议定义
├── ScannerRegistry.swift     # Scanner 注册中心
├── UsageStore.swift          # 数据引擎
├── UsageParser.swift         # JSONL 解析器
├── BalanceFetcher.swift      # 余额查询
├── Pricing.swift             # 价格表
├── KeychainStore.swift       # Keychain 封装
├── Models.swift              # 数据模型
├── TokenWatchApp.swift       # App 入口
├── Views/
│   ├── MenuBarView.swift     # 菜单栏面板
│   ├── DashboardView.swift   # 详情窗口
│   ├── SettingsView.swift    # 设置
│   └── AgentTabView.swift    # Agent 管理
└── Scanners/                 # 各 Agent 实现
    ├── ClaudeCodeScanner.swift
    ├── CodexScanner.swift
    ├── CursorScanner.swift
    ├── ProxyLogScanner.swift
    ├── CodeBuddyScanner.swift
    ├── WorkBuddyScanner.swift
    ├── TraeScanner.swift
    ├── TraeWorkScanner.swift
    ├── QoderWorkScanner.swift
    └── GenericJSONLScanner.swift
proxy/
├── server.js                 # 代理服务
└── config.json               # 路由配置
```

## 常见问题

**菜单栏无数据?** 确保至少有一个 Agent 在运行(Claude Code / Codex CLI 等),数据在 2 秒内自动出现。

**某个 Agent 不识别?** 在设置→Agent 监控中,确认开关已打开,路径存在。也可手动添加自定义 Agent。

**余额显示"未配置"?** 在设置→API 余额中填写该平台的 API Key。

**费用不准确?** 默认价格为估算,在设置→模型价格中按你的实际渠道价格修改。

**刷新数据归零?** 已在 v0.1.0 修复,如仍出现请提 Issue。

## License

MIT

## 贡献

欢迎提 Issue / PR。新增 Agent Scanner 请参考 `AgentScanner` 协议和现有实现。
