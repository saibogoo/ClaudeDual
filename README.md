# ClaudexDual - Third-Party Model Manager for Claude and Codex

[English](README.md) · [简体中文](README_zh.md)

ClaudexDual (formerly ClaudeDual) is a macOS desktop app for managing third-party inference profiles, isolated instances, and local proxies for Claude Desktop and Codex. Both clients share a profile list with separate API endpoints and model mappings. Claude Developer Mode can be enabled with one click.

The product is now named **ClaudexDual**. The GitHub repository URL and internal `ClaudeDual` identifiers remain unchanged to preserve existing settings, credentials, and updates. When manually upgrading from ClaudeDual, install ClaudexDual.app and remove the old ClaudeDual.app after verifying the new app works; keep your user data.

## 📸 Screenshots

![Status](docs/screenshots/status.png)

| Configuration | Logs |
|:---:|:---:|
| ![Configuration](docs/screenshots/configuration.png) | ![Logs](docs/screenshots/logs.png) |

## 🚀 Features

### 🔄 Isolated Instance Management
- **Independent Running**: Launch completely isolated instances from main Claude Desktop via `--user-data-dir` parameter
- **Codex Isolation**: Uses a separate `CODEX_HOME` and desktop data directory, preserving existing Codex settings
- **Status Monitoring**: Real-time display of instance running status, PID and more
- **One-Click Control**: Convenient start/stop control with graceful termination

### ⚙️ Multi-Configuration Management
- **Configuration System**: Create, edit, copy, delete multiple model configurations
- **Flexible Switching**: Quick switching between different model providers and settings
- **Parameter Customization**: Configure separate Claude (Anthropic) and Codex (OpenAI) API base URLs, keys, authentication methods, model names, etc.

### 🌐 Proxy Server
- **Built-in Proxy**: Integrated Python HTTP proxy supporting request forwarding and model name mapping
- **Authentication Conversion**: Supports multiple authentication methods: Bearer, x-api-key, anthropic-api-key
- **Port Adaptation**: Automatically detects port conflicts, dynamically allocates available ports

### 🔄 CC-Switch Mode
- **Seamless Integration**: Direct integration with [CC-Switch](https://github.com/musistudio/ccswitch) local gateway service
- **Independent Configuration**: Uses CC-Switch's built-in model mapping and authentication configuration
- **Mode Switching**: Freely switch between CC-Switch mode and local proxy mode

### 💡 User Experience
- **Intuitive Interface**: Modern SwiftUI interface with real-time status cards
- **Developer Mode**: One-click enable Claude Desktop Developer Mode
- **Log Tracking**: Detailed operation logs and status information

## 🏗️ Core Principles

### Isolated Instance Launch
```bash
open -n -a /Applications/Claude.app --args --user-data-dir=~/Library/Application\ Support/ClaudeDual-3p
```

- Run Claude Desktop in an independent data directory, completely isolated from the main app
- Avoids configuration conflicts, allows running multiple Claude instances simultaneously

### Configuration Injection Mechanism
The app generates and writes configuration files to the isolated instance's `configLibrary/` directory before launching:

**Inference Configuration** (`7595758f-...json`):
```json
{
  "coworkEgressAllowedHosts": ["*"],
  "inferenceProvider": "gateway",
  "inferenceGatewayBaseUrl": "http://127.0.0.1:3456/",
  "inferenceGatewayApiKey": "claude-dual-local-proxy",
  "inferenceGatewayAuthScheme": "bearer",
  "inferenceModels": [
    "claude-fable-5",
    "claude-opus-5",
    "claude-sonnet-5",
    "claude-haiku-4-5-20251001"
  ]
}
```

### Proxy Server Workflow
1. **Request Reception**: Proxy server listens on specified port (default 3456)
2. **Model Mapping**: Converts Claude frontend model names to upstream actual model names
3. **Authentication Processing**: Adds appropriate authentication headers based on configuration
4. **Request Forwarding**: Forwards processed requests to upstream API
5. **Response Return**: Streams upstream response back to Claude

### CC-Switch Integration
When CC-Switch mode is enabled:
- Bypass local proxy, directly point gateway address to CC-Switch service
- No need to duplicate model mapping and authentication in ClaudexDual
- Leverage CC-Switch's advanced routing and load balancing features

## 🔧 Installation & Usage

### System Requirements
- macOS 13.0 or higher
- Claude Desktop or Codex installed, depending on the client you use
- Python 3 for the built-in proxy

### Installation Steps
1. Download the [latest released DMG](https://github.com/saibogoo/ClaudeDual/releases/latest)
2. Drag to Applications folder
3. First run requires allowing in privacy settings

If macOS blocks the app with "unverified developer", run:

```bash
sudo xattr -r -d com.apple.quarantine /Applications/ClaudexDual.app
```

### Online Updates

ClaudexDual checks GitHub Releases at startup. You can also check manually under **About → Online Update**. When a new version is available:

1. Click **Download and Install**
2. ClaudexDual verifies both the asset size and the SHA-256 digest provided by GitHub
3. After verification it replaces the app in place and relaunches automatically — no dragging required

If the automatic install cannot proceed (for example the install directory is not writable), ClaudexDual restores the previous version and opens the DMG so you can install manually.

### Build from Source

ClaudexDual is a single-file SwiftUI app — no Xcode project required.

```bash
# Compile a standalone executable
swiftc -parse-as-library ClaudexDualApp.swift -o ClaudexDual

# Or package a full .app bundle (icon + proxy script + Info.plist)
tools/PackageApp.sh
```

Requires macOS 13.0+, Swift toolchain (Xcode Command Line Tools), and Python 3 for the built-in proxy.

### Basic Usage Flow
1. **Check Status**: Select Claude or Codex and confirm that client is installed; enable Developer Mode when using Claude
2. **Create Configuration**: Add your third-party model provider settings in configuration page
3. **Select Mode**:
   - Local Proxy Mode: ClaudexDual manages all configurations
   - CC-Switch Mode: Connect to existing CC-Switch service
4. **Start Instance**: Click start button, wait for isolated instance to load
5. **Start Using**: Experience third-party models in the new instance

## 📋 Upstream API Requirements

Claude requires Anthropic Messages compatibility (`/v1/messages`); Codex requires OpenAI Responses compatibility (`/v1/responses`). An OpenAI-compatible service that only supports Chat Completions is not sufficient. The local proxy handles mapping and authentication, not conversion between these protocols.

## Model Mapping (v1.3.2)

- Claude: configure display aliases and upstream models for Sonnet, Opus, Fable, and Haiku; use Subagent as the fallback target for unmatched models.
- Declare one-million-token context support; actual context availability depends on the upstream service and client.
- Codex: configure an independent local model ID and upstream request model. The client menu may still show `Custom`; mapping controls the actual request.
- Fetch the provider model list and apply its first model to the selected client with one click.
- Browsing profiles does not proactively read Keychain; leaving the key blank while editing preserves the saved credential.

## ⚡ Advanced Features

### Outbound Host Whitelist
Customize `coworkEgressAllowedHosts` to control external domains accessible to Claude.

### Custom Model Mapping
Through the proxy server, map Claude frontend displayed model names to actual upstream model names.

### CC-Switch Delegation
Use CC-Switch as the upstream gateway when you want model routing, authentication, and load balancing to be managed outside ClaudexDual.

## 🛡️ Security Notice

- API keys are stored in macOS Keychain and used to authenticate requests to your configured upstream service
- Isolated instances ensure third-party model configurations don't affect main app
- The local proxy forwards request content to your configured upstream service; its data policies apply

## 📚 Documentation

- [第三方模型配置指南](docs/第三方模型配置指南.md) — Full guide to Developer Mode and third-party inference (Chinese)
- [Codex 隔离实例](docs/Codex隔离实例.md) — Share inference profiles while isolating Codex state and desktop data (Chinese)
- [安装说明](docs/安装说明.md) — Installation notes (Chinese)
- [发布流程规范](docs/发布流程规范.md) — Release process and versioning rules (Chinese)

> Codex uses the OpenAI Responses API (`/v1/responses`). An Anthropic-Messages-only upstream will return 404; use an OpenAI Responses-compatible endpoint or gateway for Codex.

## 🤝 Contributing

Welcome to submit Issues and Pull Requests to improve ClaudexDual!

## 📄 License

[MIT License](LICENSE)

---

*ClaudexDual lets you easily experience various third-party models in Claude and Codex and enjoy the fun of AI development!*
