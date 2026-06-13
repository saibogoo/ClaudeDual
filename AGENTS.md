# AGENTS.md

This file provides guidance to Codex when working with code in this repository.

## 项目简介

ClaudeDual 是一个 macOS SwiftUI 桌面应用，用于管理 Claude Desktop Developer Mode、第三方推理配置和隔离实例启动。它通过 `--user-data-dir` 参数启动独立的 Claude Desktop 实例，并在隔离数据目录中写入第三方推理配置。

## 构建与运行

本项目是单文件 SwiftUI 应用，没有 Xcode 工程文件或 Package.swift。

### 编译为可执行文件

```bash
swiftc -parse-as-library -module-cache-path /private/tmp/claude-dual-swift-module-cache ClaudeDualApp.swift -o ClaudeDual
```

### 打包为 .app

```bash
tools/PackageApp.sh
```

打包脚本会复用 `Resources/ClaudeDual.icns`，不要每次重新生成图标。只有该文件缺失或明确需要更新图标时，PackageApp.sh 会自动用 `Resources/icon.png` + `tools/BuildIcns.py` 重新生成。

### 打包 DMG

```bash
hdiutil create -volname ClaudeDual -srcfolder /private/tmp/claude-dual-dmg-final-20260517 -ov -format UDZO ClaudeDual.dmg
```

发布前确认 DMG 内包含：

- `ClaudeDual.app`
- `Applications` 快捷方式
- `docs/安装说明.md`

## 架构概览

所有 Swift 代码集中在 `ClaudeDualApp.swift` 中：

1. `ClaudeDualApp`：`@main` 入口，创建 `WindowGroup` 承载 `ContentView`
2. `ClaudeDualManager`：`ObservableObject`，处理状态管理、配置写入、代理启动和外部进程操作
3. SwiftUI 视图层：状态、配置、日志、关于四个 Tab

Python 代理脚本位于 `Resources/proxy_server.py`，负责本地请求透传、模型名映射和认证头转换。

## 核心机制

### 隔离实例启动

通过 `Process` 调用：

```bash
open -n -a /Applications/Claude.app --args --user-data-dir="$HOME/Library/Application Support/ClaudeDual-3p"
```

### 开发者模式初始化

一键开启开发者模式时会创建 `~/Library/Application Support/ClaudeDual-3p`，并写入：

- `claude_desktop_config.json`：包含 `deploymentMode = "3p"`
- `developer_settings.json`：包含 `allowDevTools = true`
- `config.json`：基础偏好
- `configLibrary/_meta.json`
- `configLibrary/7595758f-4aab-4d2e-9bf8-b0abfc5616e4.json`

### 推理配置

写入的推理配置使用：

- `inferenceProvider = gateway`
- `inferenceGatewayBaseUrl`
- `inferenceGatewayApiKey`
- `inferenceGatewayAuthScheme`
- `inferenceModels`：Claude 可见的模型别名列表，例如 `claude-sonnet-4-6`、`claude-opus-4-7`

`inferenceModels` 写入的是 Claude 前端可见的别名模型，用来跳过 gateway `/v1/models` 自动发现；真实上游模型仍由本地代理或 CC-Switch 选择。

### 代理模式

- 本地代理：ClaudeDual 启动 `Resources/proxy_server.py`，将 Claude 请求映射到当前配置的上游模型。
- CC-Switch：ClaudeDual 直接把 gateway 指向 CC-Switch 地址，模型映射和认证由 CC-Switch 管理。

## 修改注意事项

- 不要提交 `ClaudeDual.app/`、`ClaudeDual.dmg`、`ClaudeDual` 等构建产物。
- 不要提交真实 API Key。配置文件和用户数据应只存在用户本机。
- 修改代理脚本后，需要重新复制到 app bundle 的 `Contents/Resources/` 并重建 DMG。
- 运行进程检测依赖 `ps` 中的 `--user-data-dir` 参数，改启动参数时要同步检查停止逻辑。
