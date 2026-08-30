# Codex 隔离实例

ClaudexDual 可以在不修改原有 `~/.codex` 的前提下，启动第二个 Codex 实例并使用自定义推理配置。

Claude 与 Codex 共用同一份配置列表和同一个“当前配置”。在任意客户端下新建、修改、复制、删除或激活配置，另一个客户端会立即使用同一结果。只有应用数据目录、进程、状态和本地代理端口按客户端隔离。

## 隔离边界

Codex 隔离实例使用独立的根目录：

```text
~/Library/Application Support/ClaudeDual/CodexInstances/default/
├── codex-home/       # config.toml、认证状态、会话、SQLite、日志等
└── electron-data/   # Codex/ChatGPT 桌面端用户数据
```

启动时同时设置：

- `CODEX_HOME=.../codex-home`
- `--user-data-dir=.../electron-data`

因此原有 Codex 仍继续使用它自己的 `~/.codex` 和默认桌面数据目录，两个实例的配置、认证、会话、数据库和日志互不混用。

## 使用方法

1. 在“配置管理”中维护共享配置，可选择本地代理、CC Switch 或直连。
2. 在左侧顶部切换到“Codex”，回到“状态”。
3. 点击“一键初始化”生成隔离配置。
4. 点击“启动”打开第二个 Codex 实例；“停止”只匹配并终止该隔离目录对应的进程。

## 配置与密钥

- Codex 自定义 provider 使用 Responses API（`wire_api = "responses"`）。
- 共享配置的 API 密钥保存在 macOS 钥匙串，不写入 UserDefaults 或生成的 Codex `config.toml`。启动时仅由 ClaudexDual 主进程按需读取一次，并通过子进程环境变量临时传递；代理和 Codex 不会再各自调用 `security`，避免重复的钥匙串授权提示。
- 本地代理模式使用单独端口，与 Claude 代理的进程、配置和端口独立。
