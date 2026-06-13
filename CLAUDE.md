# CLAUDE.md

This file provides guidance to Claude Code when working with code in this repository.

## 项目简介

ClaudeDual 是一个 macOS SwiftUI 桌面应用，用于一键开启 Claude Desktop Developer Mode、管理第三方推理配置，并启动隔离的 Claude Desktop 实例。

## 构建与运行

本项目没有 Xcode 工程文件或 Package.swift，主要代码在 `ClaudeDualApp.swift`。

### 编译

```bash
swiftc -parse-as-library -module-cache-path /private/tmp/claude-dual-swift-module-cache ClaudeDualApp.swift -o ClaudeDual
```

### 打包为 .app

```bash
tools/PackageApp.sh
```

打包脚本会复用 `Resources/ClaudeDual.icns`，不要每次重新生成图标。只有缺少该文件或明确需要更新图标时才重新生成 iconset / icns。

### 运行

直接双击 `ClaudeDual.app`，或执行 `./ClaudeDual`。

SwiftUI 应用需要 macOS 图形环境。调试 UI 时可在 Xcode 中打开 `ClaudeDualApp.swift`。

## 架构概览

- `ClaudeDualApp`：应用入口
- `ClaudeDualManager`：配置、状态、代理和外部进程管理
- `ContentView`：主界面，包含状态、配置、日志、关于四个 Tab
- `Resources/proxy_server.py`：本地 HTTP 代理，负责模型名映射和认证头转换

## 核心路径

| 路径 | 说明 |
|------|------|
| `/Applications/Claude.app` | 目标 Claude Desktop 应用 |
| `~/Library/Application Support/ClaudeDual-3p` | 隔离实例数据目录 |
| `~/Library/Application Support/ClaudeDual-3p/configLibrary` | 第三方推理配置目录 |

## 核心机制

ClaudeDual 使用以下命令启动隔离实例：

```bash
open -n -a /Applications/Claude.app --args --user-data-dir="$HOME/Library/Application Support/ClaudeDual-3p"
```

开启开发者模式时写入：

- `claude_desktop_config.json`
- `developer_settings.json`
- `config.json`
- `configLibrary/_meta.json`
- `configLibrary/7595758f-4aab-4d2e-9bf8-b0abfc5616e4.json`

第三方推理配置采用 gateway provider，并在 `inferenceModels` 中写入 Claude 可见的模型别名，以跳过 gateway `/v1/models` 自动发现；真实上游模型名由 ClaudeDual 本地代理或 CC-Switch 处理。

## 修改注意事项

- API Key 只应保存在用户本机配置中，不要提交真实密钥。
- 构建产物 `ClaudeDual`、`ClaudeDual.app/`、`ClaudeDual.dmg` 不应提交。
- 修改 `Resources/proxy_server.py` 后，重新打包时必须复制到 app bundle。
- `legacyDataDir` 只用于从旧的 `Claude-Kimi-3p` 数据目录迁移，保留是兼容设计。
