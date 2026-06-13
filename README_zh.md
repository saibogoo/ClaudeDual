# ClaudeDual - Claude Desktop 第三方模型管理器

[English](README.md) · [简体中文](README_zh.md)

ClaudeDual 是一款专为 Claude Desktop 用户设计的 macOS 桌面应用，用于管理第三方模型配置并开启 Developer Mode（开发者模式）。通过隔离实例启动和内置代理服务器，你可以轻松接入各种第三方模型服务商。

## 📸 界面预览

| 状态 | 配置 | 日志 |
|:---:|:---:|:---:|
| ![状态](docs/screenshots/status.png) | ![配置](docs/screenshots/configuration.png) | ![日志](docs/screenshots/logs.png) |

## 🚀 功能特性

### 🔄 隔离实例管理
- **独立运行**：通过 `--user-data-dir` 参数从主 Claude Desktop 启动完全隔离的实例
- **状态监控**：实时显示实例运行状态、PID 等信息
- **一键控制**：便捷的启动/停止控制，支持优雅终止

### ⚙️ 多配置管理
- **配置系统**：创建、编辑、复制、删除多套模型配置
- **灵活切换**：在不同模型服务商和设置之间快速切换
- **参数自定义**：API 地址、密钥、认证方式、模型名称等完全可配置

### 🌐 代理服务器
- **内置代理**：集成 Python HTTP 代理，支持请求转发和模型名称映射
- **认证转换**：支持多种认证方式：Bearer、x-api-key、anthropic-api-key
- **端口自适应**：自动检测端口冲突，动态分配可用端口

### 🔄 CC-Switch 模式（新）
- **无缝集成**：直接对接 [CC-Switch](https://github.com/musistudio/ccswitch) 本地网关服务
- **独立配置**：复用 CC-Switch 内置的模型映射和认证配置
- **模式切换**：在 CC-Switch 模式和本地代理模式之间自由切换

### 💡 使用体验
- **直观界面**：现代化 SwiftUI 界面，实时状态卡片
- **开发者模式**：一键开启 Claude Desktop 开发者模式
- **日志追踪**：详细的操作日志和状态信息

## 🏗️ 核心原理

### 隔离实例启动
```bash
open -n -a /Applications/Claude.app --args --user-data-dir=~/Library/Application\ Support/ClaudeDual-3p
```

- 在独立的数据目录中运行 Claude Desktop，与主应用完全隔离
- 避免配置冲突，允许同时运行多个 Claude 实例

### 配置注入机制
应用在启动前会生成配置文件并写入隔离实例的 `configLibrary/` 目录：

**推理配置**（`7595758f-...json`）：
```json
{
  "coworkEgressAllowedHosts": ["*"],
  "inferenceProvider": "gateway",
  "inferenceGatewayBaseUrl": "http://127.0.0.1:3456/",
  "inferenceGatewayApiKey": "claude-dual-local-proxy",
  "inferenceGatewayAuthScheme": "bearer",
  "inferenceModels": [
    "claude-sonnet-4-6",
    "claude-opus-4-7",
    "claude-haiku-4-5",
    "claude-opus-4-7[1m]"
  ]
}
```

### 代理服务器工作流程
1. **接收请求**：代理服务器监听指定端口（默认 3456）
2. **模型映射**：将 Claude 前端模型名转换为上游真实模型名
3. **认证处理**：根据配置添加对应的认证头
4. **请求转发**：将处理后的请求转发到上游 API
5. **响应返回**：将上游响应流式回传给 Claude

### CC-Switch 集成
启用 CC-Switch 模式时：
- 跳过本地代理，将 gateway 地址直接指向 CC-Switch 服务
- 无需在 ClaudeDual 中重复配置模型映射和认证
- 复用 CC-Switch 的高级路由和负载均衡能力

## 🔧 安装与使用

### 系统要求
- macOS 13.0 或更高版本
- 已安装 Claude Desktop

### 安装步骤
1. 下载最新发布的 DMG 文件
2. 拖入「应用程序」文件夹
3. 首次运行需在隐私设置中允许

如果 macOS 提示「无法验证开发者」，可执行：

```bash
sudo xattr -r -d com.apple.quarantine /Applications/ClaudeDual.app
```

### 从源码构建

ClaudeDual 是单文件 SwiftUI 应用，无需 Xcode 工程。

```bash
# 编译为独立可执行文件
swiftc -parse-as-library ClaudeDualApp.swift -o ClaudeDual

# 或打包完整的 .app（图标 + 代理脚本 + Info.plist）
tools/PackageApp.sh
```

需要 macOS 13.0+、Swift 工具链（Xcode 命令行工具），以及用于内置代理的 Python 3。

### 基本使用流程
1. **检查状态**：确认 Claude Desktop 已安装、开发者模式已开启
2. **创建配置**：在配置页添加你的第三方模型服务商设置
3. **选择模式**：
   - 本地代理模式：由 ClaudeDual 管理所有配置
   - CC-Switch 模式：对接已有的 CC-Switch 服务
4. **启动实例**：点击启动按钮，等待隔离实例加载
5. **开始使用**：在新实例中体验第三方模型

## 📋 支持的模型服务商

- **DashScope**（通义千问系列）
- **百炼**（百炼平台）
- **Kimi**（Moonshot AI）
- **零一万物**（yi 系列）
- **智谱 AI**（glm 系列）
- **以及任何其他兼容 OpenAI 的 API 服务**

## ⚡ 进阶功能

### 出站主机白名单
自定义 `coworkEgressAllowedHosts`，控制 Claude 可访问的外部域名。

### 自定义模型映射
通过代理服务器，将 Claude 前端显示的模型名映射到上游真实模型名。

### CC-Switch 委托
当你希望模型路由、认证和负载均衡在 ClaudeDual 之外统一管理时，可将 CC-Switch 作为上游网关。

## 🛡️ 安全说明

- API 密钥仅保存在本地，不会上传到任何服务器
- 隔离实例确保第三方模型配置不影响主应用
- 所有网络请求均在本地处理，保护用户数据隐私

## 📚 文档

- [第三方模型配置指南](docs/第三方模型配置指南.md) —— Developer Mode 与第三方推理完整指南
- [安装说明](docs/安装说明.md) —— 安装与常见问题

## 🤝 贡献

欢迎提交 Issue 和 Pull Request 来改进 ClaudeDual！

## 📄 许可证

[MIT License](LICENSE)

---

*ClaudeDual 让你在 Claude 生态中轻松体验各种第三方模型，享受 AI 开发的乐趣！*
