import SwiftUI
import AppKit
import Darwin

// MARK: - Config Profile Model

struct ConfigProfile: Identifiable, Codable, Equatable {
    var id: UUID
    var name: String
    var apiBaseUrl: String
    var apiKey: String
    var authScheme: String?
    var modelName: String
    var allowedHosts: String

    // Proxy mode: nil or "localProxy" = built-in proxy, "ccSwitch" = CC-Switch gateway
    var proxyMode: String?
    var ccSwitchUrl: String?

    static let defaultUpstreamModel = "provider-default-model"
    static let defaultCcSwitchUrl = "http://127.0.0.1:15721"
    static let defaultInferenceModels = [
        "claude-fable-5",
        "claude-opus-5",
        "claude-sonnet-5",
        "claude-haiku-4-5-20251001",
        "claude-opus-4-8",
        "claude-opus-4-7",
        "claude-opus-4-6",
        "claude-sonnet-4-6"
    ]

    static func makeDefault() -> ConfigProfile {
        ConfigProfile(
            id: UUID(),
            name: "Default Gateway",
            apiBaseUrl: "https://coding.dashscope.aliyuncs.com/apps/anthropic",
            apiKey: "",
            authScheme: "bearer",
            modelName: defaultUpstreamModel,
            allowedHosts: "*"
        )
    }

    var effectiveAuthScheme: String {
        authScheme ?? "bearer"
    }

    var effectiveApiBaseUrl: String {
        apiBaseUrl.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var effectiveApiKey: String {
        apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var effectiveUpstreamModel: String {
        let trimmed = modelName.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? Self.defaultUpstreamModel : trimmed
    }

    var effectiveProxyMode: String {
        proxyMode ?? "localProxy"
    }

    var effectiveCcSwitchUrl: String {
        let url = ccSwitchUrl?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return url.isEmpty ? Self.defaultCcSwitchUrl : url
    }

    var isCcSwitchMode: Bool {
        effectiveProxyMode == "ccSwitch"
    }

    var maskedApiKey: String {
        let key = effectiveApiKey
        if key.count > 16 {
            return String(key.prefix(12)) + "****" + String(key.suffix(4))
        }
        return key
    }
}

// MARK: - Log Types

enum LogType {
    case success, error, warning, info

    var color: Color {
        switch self {
        case .success: return AppTheme.success
        case .error: return AppTheme.danger
        case .warning: return AppTheme.warning
        case .info: return AppTheme.info
        }
    }

    var icon: String {
        switch self {
        case .success: return "checkmark.circle.fill"
        case .error: return "xmark.circle.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .info: return "info.circle.fill"
        }
    }
}

struct LogEntry: Identifiable {
    let id = UUID()
    let time: String
    let message: String
    let type: LogType
}

// MARK: - App Entry Point

@main
struct ClaudeDualApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .windowStyle(.titleBar)
        .defaultSize(width: 1120, height: 720)
    }
}

// MARK: - Tab Enumeration

enum AppTab: String, CaseIterable {
    case status = "状态"
    case configuration = "配置"
    case logs = "日志"
    case about = "关于"

    var icon: String {
        switch self {
        case .status: return "gauge.with.dots.needle.67percent"
        case .configuration: return "gearshape.2"
        case .logs: return "doc.text.below.ecg"
        case .about: return "info.circle"
        }
    }

    var subtitle: String {
        switch self {
        case .status: return "运行概览"
        case .configuration: return "模型与网关"
        case .logs: return "运行记录"
        case .about: return "版本信息"
        }
    }
}

// MARK: - Visual System

enum AppTheme {
    static let canvas = adaptive(light: rgb(250, 249, 246), dark: rgb(29, 28, 26))
    static let sidebar = adaptive(light: rgb(242, 239, 234), dark: rgb(38, 36, 33))
    static let surface = adaptive(light: rgb(255, 255, 255), dark: rgb(41, 39, 36))
    static let surfaceSoft = adaptive(light: rgb(251, 250, 248), dark: rgb(37, 35, 32))
    static let ink = adaptive(light: rgb(28, 27, 25), dark: rgb(242, 238, 231))
    static let inkSecondary = adaptive(light: rgb(74, 70, 62), dark: rgb(209, 203, 192))
    static let muted = adaptive(light: rgb(138, 133, 124), dark: rgb(159, 153, 143))
    static let border = adaptive(light: rgb(231, 226, 217), dark: rgb(58, 55, 50))
    static let borderSoft = adaptive(light: rgb(241, 237, 230), dark: rgb(52, 49, 45))
    static let danger = adaptive(light: rgb(214, 58, 63), dark: rgb(255, 105, 109))
    static let success = adaptive(light: rgb(18, 161, 80), dark: rgb(85, 201, 130))
    static let focus = adaptive(light: rgb(10, 108, 255), dark: rgb(101, 167, 255))
    static let info = focus
    static let warning = adaptive(light: rgb(232, 137, 12), dark: rgb(242, 163, 60))
    static let accent = adaptive(light: rgb(138, 61, 15), dark: rgb(240, 174, 117))
    static let accentSoft = adaptive(light: rgb(237, 231, 220), dark: rgb(64, 57, 48))

    private static func rgb(_ red: CGFloat, _ green: CGFloat, _ blue: CGFloat) -> NSColor {
        NSColor(srgbRed: red / 255, green: green / 255, blue: blue / 255, alpha: 1)
    }

    private static func adaptive(light: NSColor, dark: NSColor) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
        })
    }
}

enum AppAppearance: String, CaseIterable, Identifiable {
    case system, light, dark

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: return "跟随系统"
        case .light: return "亮色"
        case .dark: return "暗色"
        }
    }

    var icon: String {
        switch self {
        case .system: return "circle.lefthalf.filled"
        case .light: return "sun.max"
        case .dark: return "moon"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}

struct AppCard: ViewModifier {
    var cornerRadius: CGFloat = 10
    var borderColor: Color = AppTheme.border

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(AppTheme.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(borderColor, lineWidth: 1)
            )
    }
}

extension View {
    func appCard(cornerRadius: CGFloat = 10, borderColor: Color = AppTheme.border) -> some View {
        modifier(AppCard(cornerRadius: cornerRadius, borderColor: borderColor))
    }
}

// MARK: - Manager (Business Logic)

class ClaudeDualManager: ObservableObject {
    @Published var isClaudeInstalled = false
    @Published var isInstanceRunning = false
    @Published var isInstanceStarting = false
    @Published var isInstanceStopping = false
    @Published var isConfigured = false
    @Published var isDeveloperModeEnabled = false
    @Published var instancePID: String = ""
    @Published var logs: [LogEntry] = []

    // Multi-config support
    @Published var profiles: [ConfigProfile] = []
    @Published var activeProfileId: UUID?

    // Proxy support
    @Published var isProxyRunning = false
    @Published var proxyPort: Int

    var activeProfile: ConfigProfile? {
        profiles.first { $0.id == activeProfileId }
    }

    let dataDir: String
    let configDir: String
    let legacyDataDir: String
    let claudeApp = "/Applications/Claude.app"
    let configId = "7595758f-4aab-4d2e-9bf8-b0abfc5616e4"
    let localProxyApiKey = "claude-dual-local-proxy"

    private var proxyProcess: Process?
    private var proxyScriptPath: String?
    private var proxyConfigPath: String?

    private let defaults = UserDefaults.standard
    private let profilesKey = "ck.profiles"
    private let activeProfileKey = "ck.activeProfileId"
    private let proxyPortKey = "ck.proxyPort"
    private let legacyDefaultsDomains = [
        "com.local.ClaudeDual",
        "com.claudedual.app",
        "ClaudeDual",
        "com.saibogoo.claude-kimi"
    ]

    init() {
        NSLog("[CD] Manager init start")
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        dataDir = "\(home)/Library/Application Support/ClaudeDual-3p"
        legacyDataDir = "\(home)/Library/Application Support/Claude-Kimi-3p"
        configDir = "\(dataDir)/configLibrary"

        proxyPort = defaults.integer(forKey: proxyPortKey)
        if proxyPort == 0 { proxyPort = 3456 }

        loadProfiles()
        migrateLegacyDataIfNeeded()
        NSLog("[CD] Manager init: profiles loaded, count=\(profiles.count)")

        // Defer heavy I/O to background to avoid blocking UI init
        DispatchQueue.global(qos: .userInitiated).async {
            let installed = FileManager.default.fileExists(atPath: self.claudeApp)
            let configFile = "\(self.configDir)/\(self.configId).json"
            let configured = FileManager.default.fileExists(atPath: configFile)
            let developerModeEnabled = self.detectDeveloperModeEnabled()
            DispatchQueue.main.async {
                self.isClaudeInstalled = installed
                self.isConfigured = configured
                self.isDeveloperModeEnabled = developerModeEnabled
                NSLog("[CD] Manager init: async status updated, installed=\(installed), configured=\(configured), developerMode=\(developerModeEnabled)")
            }
            self.checkRunningInstance()
            self.checkProxyRunning()
        }
    }

    private func migrateLegacyDataIfNeeded() {
        guard !FileManager.default.fileExists(atPath: dataDir),
              FileManager.default.fileExists(atPath: legacyDataDir) else {
            return
        }

        do {
            try FileManager.default.copyItem(atPath: legacyDataDir, toPath: dataDir)
            addLog("📦 已迁移旧数据目录", type: .info)
        } catch {
            addLog("⚠️ 迁移旧数据目录失败: \(error.localizedDescription)", type: .warning)
        }
    }

    // MARK: - Profile Management

    private func loadProfiles() {
        let loaded = loadProfilesFromDefaults(defaults)
        let legacyLoaded = bestLegacyProfiles()
        let selected = shouldPreferLegacyProfiles(current: loaded?.profiles, legacy: legacyLoaded?.profiles) ? legacyLoaded : loaded

        if let selected = selected {
            profiles = selected.profiles
            activeProfileId = selected.activeProfileId
            if let port = selected.proxyPort, port > 1024 && port < 65535 {
                proxyPort = port
                defaults.set(port, forKey: proxyPortKey)
            }
        } else {
            profiles = [ConfigProfile.makeDefault()]
        }

        normalizeProfiles()

        if activeProfileId == nil || !profiles.contains(where: { $0.id == activeProfileId }) {
            activeProfileId = profiles.first?.id
        }

        saveProfilesToDefaults()
    }

    private func loadProfilesFromDefaults(_ store: UserDefaults) -> (profiles: [ConfigProfile], activeProfileId: UUID?, proxyPort: Int?)? {
        guard let data = store.data(forKey: profilesKey),
              let decoded = try? JSONDecoder().decode([ConfigProfile].self, from: data),
              !decoded.isEmpty else {
            return nil
        }

        var activeId: UUID?
        if let activeIdString = store.string(forKey: activeProfileKey),
           let id = UUID(uuidString: activeIdString),
           decoded.contains(where: { $0.id == id }) {
            activeId = id
        }

        let port = store.integer(forKey: proxyPortKey)
        return (decoded, activeId, port == 0 ? nil : port)
    }

    private func bestLegacyProfiles() -> (profiles: [ConfigProfile], activeProfileId: UUID?, proxyPort: Int?)? {
        var best: (profiles: [ConfigProfile], activeProfileId: UUID?, proxyPort: Int?)?
        var bestScore = -1

        for domain in legacyDefaultsDomains {
            guard let store = UserDefaults(suiteName: domain),
                  let loaded = loadProfilesFromDefaults(store) else {
                continue
            }

            let score = profileRecoveryScore(loaded.profiles)
            if score > bestScore {
                best = loaded
                bestScore = score
            }
        }

        return best
    }

    private func shouldPreferLegacyProfiles(current: [ConfigProfile]?, legacy: [ConfigProfile]?) -> Bool {
        guard let legacy = legacy else { return false }
        guard let current = current else { return true }

        return isPlaceholderProfiles(current) && profileRecoveryScore(legacy) > profileRecoveryScore(current)
    }

    private func isPlaceholderProfiles(_ candidate: [ConfigProfile]) -> Bool {
        guard candidate.count == 1, let profile = candidate.first else { return false }
        return profile.name == ConfigProfile.makeDefault().name &&
            profile.effectiveApiKey.isEmpty &&
            profile.effectiveUpstreamModel == ConfigProfile.defaultUpstreamModel
    }

    private func profileRecoveryScore(_ candidate: [ConfigProfile]) -> Int {
        candidate.reduce(0) { score, profile in
            var value = 1
            if !profile.effectiveApiKey.isEmpty { value += 4 }
            if profile.effectiveUpstreamModel != ConfigProfile.defaultUpstreamModel { value += 2 }
            if profile.isCcSwitchMode { value += 1 }
            return score + value
        }
    }

    private func normalizeProfiles() {
        profiles = profiles.map { profile in
            var normalized = profile
            normalized.name = profile.name.trimmingCharacters(in: .whitespacesAndNewlines)
            normalized.apiBaseUrl = profile.effectiveApiBaseUrl
            normalized.apiKey = profile.effectiveApiKey
            normalized.modelName = profile.effectiveUpstreamModel
            normalized.allowedHosts = profile.allowedHosts.trimmingCharacters(in: .whitespacesAndNewlines)
            if let url = profile.ccSwitchUrl {
                normalized.ccSwitchUrl = url.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            return normalized
        }
    }

    private func saveProfilesToDefaults() {
        if let data = try? JSONEncoder().encode(profiles) {
            defaults.set(data, forKey: profilesKey)
        }
        if let id = activeProfileId {
            defaults.set(id.uuidString, forKey: activeProfileKey)
        }
    }

    func addProfile(name: String, apiBaseUrl: String, apiKey: String, authScheme: String, modelName: String, allowedHosts: String) -> ConfigProfile {
        let profile = ConfigProfile(
            id: UUID(),
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            apiBaseUrl: apiBaseUrl.trimmingCharacters(in: .whitespacesAndNewlines),
            apiKey: apiKey.trimmingCharacters(in: .whitespacesAndNewlines),
            authScheme: authScheme,
            modelName: modelName.trimmingCharacters(in: .whitespacesAndNewlines),
            allowedHosts: allowedHosts.trimmingCharacters(in: .whitespacesAndNewlines)
        )
        profiles.append(profile)
        saveProfilesToDefaults()
        addLog("➕ 已添加配置: \(name)", type: .info)
        return profile
    }

    func updateProfile(id: UUID, name: String, apiBaseUrl: String, apiKey: String, authScheme: String, modelName: String, allowedHosts: String, proxyMode: String?, ccSwitchUrl: String?) {
        guard let index = profiles.firstIndex(where: { $0.id == id }) else { return }
        profiles[index].name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        profiles[index].apiBaseUrl = apiBaseUrl.trimmingCharacters(in: .whitespacesAndNewlines)
        profiles[index].apiKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        profiles[index].authScheme = authScheme
        profiles[index].modelName = modelName.trimmingCharacters(in: .whitespacesAndNewlines)
        profiles[index].allowedHosts = allowedHosts.trimmingCharacters(in: .whitespacesAndNewlines)
        profiles[index].proxyMode = proxyMode
        profiles[index].ccSwitchUrl = ccSwitchUrl
        saveProfilesToDefaults()

        if activeProfileId == id {
            if isProxyRunning {
                _ = startProxy()
            }
            saveConfigToDisk()
            addLog("✅ 已更新并激活配置: \(name)", type: .success)
        } else {
            addLog("✅ 已更新配置: \(name)", type: .success)
        }
    }

    func deleteProfile(id: UUID) {
        guard profiles.count > 1 else {
            addLog("⚠️ 至少需要保留一个配置", type: .warning)
            return
        }
        guard let index = profiles.firstIndex(where: { $0.id == id }) else { return }
        let name = profiles[index].name
        profiles.remove(at: index)

        if activeProfileId == id {
            activeProfileId = profiles.first?.id
            saveConfigToDisk()
        }

        saveProfilesToDefaults()
        addLog("🗑 已删除配置: \(name)", type: .info)
    }

    func activateProfile(id: UUID) {
        guard profiles.contains(where: { $0.id == id }) else { return }
        activeProfileId = id
        saveProfilesToDefaults()
        if isProxyRunning {
            _ = startProxy()
        }
        saveConfigToDisk()
        if let name = activeProfile?.name {
            addLog("🔀 已切换到配置: \(name)", type: .info)
        }
    }

    func duplicateProfile(id: UUID) {
        guard let profile = profiles.first(where: { $0.id == id }) else { return }
        var copy = profile
        copy.id = UUID()
        copy.name = profile.name + " 副本"
        profiles.append(copy)
        saveProfilesToDefaults()
        addLog("📋 已复制配置: \(profile.name)", type: .info)
    }

    // MARK: - Proxy Management

    func startProxy() -> Bool {
        guard let profile = activeProfile else {
            addLog("⚠️ 没有激活的配置", type: .warning)
            return false
        }

        // Stop existing proxy first
        if isProxyRunning {
            stopProxy()
        }
        cleanupStaleProxyProcesses()

        // Check Python3 availability
        guard isPython3Available() else {
            addLog("⚠️ 未检测到 Python3，将直接使用真实 API 地址（模型映射不可用）", type: .warning)
            return false
        }

        // Check port availability
        if !isPortAvailable(proxyPort) {
            addLog("⚠️ 端口 \(proxyPort) 已被占用，尝试查找可用端口...", type: .warning)
            if let newPort = findAvailablePort(startingFrom: proxyPort + 1) {
                proxyPort = newPort
                defaults.set(proxyPort, forKey: proxyPortKey)
                addLog("✅ 已切换到可用端口: \(proxyPort)", type: .success)
            } else {
                addLog("❌ 无法找到可用端口", type: .error)
                return false
            }
        }

        // Write proxy config
        let tempDir = FileManager.default.temporaryDirectory.path
        proxyConfigPath = "\(tempDir)/claude-dual-proxy-config-\(configId).json"
        proxyScriptPath = "\(tempDir)/claude-dual-proxy-script-\(configId).py"

        let proxyConfig: [String: Any] = [
            "port": proxyPort,
            "target_url": profile.effectiveApiBaseUrl,
            "api_key": profile.effectiveApiKey,
            "auth_scheme": profile.effectiveAuthScheme,
            "model_name": profile.effectiveUpstreamModel
        ]

        guard let scriptContent = loadProxyScript() else {
            addLog("❌ 无法加载代理脚本文件", type: .error)
            return false
        }

        do {
            let configData = try JSONSerialization.data(withJSONObject: proxyConfig, options: .prettyPrinted)
            try configData.write(to: URL(fileURLWithPath: proxyConfigPath!))
            try scriptContent.write(toFile: proxyScriptPath!, atomically: true, encoding: .utf8)
        } catch {
            addLog("❌ 写入代理文件失败: \(error.localizedDescription)", type: .error)
            return false
        }

        // Start proxy process
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
        task.arguments = [proxyScriptPath!, proxyConfigPath!]
        task.standardOutput = Pipe()
        task.standardError = Pipe()

        do {
            try task.run()
            proxyProcess = task
            isProxyRunning = true
            addLog("🔄 代理服务器启动中 (端口: \(proxyPort))...", type: .info)

            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                if self.isProxyRunning {
                    self.addLog("✅ 代理服务器已就绪 (端口: \(self.proxyPort))", type: .success)
                }
            }
            return true
        } catch {
            addLog("❌ 代理启动失败: \(error.localizedDescription)", type: .error)
            return false
        }
    }

    func stopProxy() {
        if let process = proxyProcess, process.isRunning {
            process.terminate()
            // Give it a moment to terminate gracefully
            DispatchQueue.global().asyncAfter(deadline: .now() + 0.5) {
                if process.isRunning {
                    process.terminate()
                }
            }
        }
        proxyProcess = nil
        isProxyRunning = false
        addLog("⏹ 代理服务器已停止", type: .info)
    }

    private func cleanupStaleProxyProcesses() {
        let pattern = "claude-dual-proxy-script-\(configId).py"
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/pkill")
        task.arguments = ["-f", pattern]
        task.standardOutput = Pipe()
        task.standardError = Pipe()
        do {
            try task.run()
            task.waitUntilExit()
        } catch {
            return
        }
        usleep(200_000)
    }

    private func isPython3Available() -> Bool {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        task.arguments = ["python3"]
        task.standardOutput = Pipe()
        task.standardError = Pipe()
        do {
            try task.run()
            task.waitUntilExit()
            return task.terminationStatus == 0
        } catch {
            return FileManager.default.fileExists(atPath: "/usr/bin/python3")
        }
    }

    private func isPortAvailable(_ port: Int) -> Bool {
        var addr = sockaddr_in()
        addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = UInt16(port).bigEndian
        addr.sin_addr.s_addr = inet_addr("127.0.0.1")

        let sock = socket(AF_INET, SOCK_STREAM, 0)
        guard sock >= 0 else { return false }
        defer { close(sock) }

        var reuse: Int32 = 1
        setsockopt(sock, SOL_SOCKET, SO_REUSEADDR, &reuse, socklen_t(MemoryLayout<Int32>.size))

        let bindResult = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(sock, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        return bindResult == 0
    }

    private func isProxyPortReachable(_ port: Int) -> Bool {
        var addr = sockaddr_in()
        addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = UInt16(port).bigEndian
        addr.sin_addr.s_addr = inet_addr("127.0.0.1")

        let sock = socket(AF_INET, SOCK_STREAM, 0)
        guard sock >= 0 else { return false }
        defer { close(sock) }

        let result = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                connect(sock, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        return result == 0
    }

    private func findAvailablePort(startingFrom port: Int) -> Int? {
        for p in port..<(port + 100) {
            if isPortAvailable(p) { return p }
        }
        return nil
    }

    private func loadProxyScript() -> String? {
        // Try loading from app bundle first
        if let bundlePath = Bundle.main.path(forResource: "proxy_server", ofType: "py") {
            return try? String(contentsOfFile: bundlePath, encoding: .utf8)
        }
        // Fallback: look in Resources/ relative to executable (for development)
        let executableDir = (CommandLine.arguments[0] as NSString).deletingLastPathComponent
        let devPath = (executableDir as NSString).appendingPathComponent("../Resources/proxy_server.py")
        return try? String(contentsOfFile: devPath, encoding: .utf8)
    }

    // MARK: - Config Persistence

    @discardableResult
    func saveConfigToDisk() -> Bool {
        guard let profile = activeProfile else {
            addLog("⚠️ 没有激活的配置", type: .warning)
            return false
        }

        do {
            try FileManager.default.createDirectory(atPath: configDir, withIntermediateDirectories: true, attributes: nil)
        } catch {
            addLog("❌ 创建目录失败: \(error.localizedDescription)", type: .error)
            return false
        }

        let hosts = profile.allowedHosts.components(separatedBy: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        // Determine gateway URL based on proxy mode
        let gatewayUrl: String
        let gatewayApiKey: String
        let gatewayAuthScheme: String
        if profile.isCcSwitchMode {
            // CC-Switch mode: point directly to CC-Switch gateway
            gatewayUrl = profile.effectiveCcSwitchUrl
            gatewayApiKey = "sk-cc-switch"
            gatewayAuthScheme = "bearer"
        } else {
            // Local proxy mode: always point to the built-in proxy so model mapping is applied.
            gatewayUrl = "http://127.0.0.1:\(proxyPort)/"
            gatewayApiKey = localProxyApiKey
            gatewayAuthScheme = "bearer"
        }

        let configObject: [String: Any] = [
            "coworkEgressAllowedHosts": hosts,
            "inferenceProvider": "gateway",
            "inferenceGatewayBaseUrl": gatewayUrl,
            "inferenceGatewayApiKey": gatewayApiKey,
            "inferenceGatewayAuthScheme": gatewayAuthScheme,
            "inferenceModels": ConfigProfile.defaultInferenceModels
        ]

        let configContent: String
        do {
            let data = try JSONSerialization.data(withJSONObject: configObject, options: .prettyPrinted)
            configContent = String(data: data, encoding: .utf8) ?? "{}"
        } catch {
            addLog("❌ 生成配置失败: \(error.localizedDescription)", type: .error)
            return false
        }

        let configPath = "\(configDir)/\(configId).json"
        do {
            try configContent.write(toFile: configPath, atomically: true, encoding: .utf8)
        } catch {
            addLog("❌ 写入配置失败: \(error.localizedDescription)", type: .error)
            return false
        }

        let metaContent = """
        {
          "appliedId": "\(configId)",
          "entries": [
            {"id": "\(configId)", "name": "Default"}
          ]
        }
        """
        let metaPath = "\(configDir)/_meta.json"
        do {
            try metaContent.write(toFile: metaPath, atomically: true, encoding: .utf8)
        } catch {
            addLog("❌ 写入元数据失败: \(error.localizedDescription)", type: .error)
            return false
        }

        addLog("✅ 配置已保存到磁盘", type: .success)
        isConfigured = true
        return true
    }

    func enableDeveloperMode() {
        guard !isInstanceStarting && !isInstanceStopping else {
            addLog("⚠️ 操作进行中，请稍候", type: .warning)
            return
        }

        do {
            try FileManager.default.createDirectory(atPath: dataDir, withIntermediateDirectories: true, attributes: nil)
        } catch {
            addLog("❌ 创建数据目录失败: \(error.localizedDescription)", type: .error)
            return
        }

        guard saveConfigToDisk() else { return }
        guard writeDesktopConfig(deploymentMode: "3p") else { return }
        guard writeDeveloperSettings() else { return }
        writeBasicConfigIfNeeded()

        isDeveloperModeEnabled = true
        addLog("✅ 开发者模式已开启", type: .success)
    }

    private func detectDeveloperModeEnabled() -> Bool {
        let configFile = "\(configDir)/\(configId).json"
        let metaFile = "\(configDir)/_meta.json"
        guard FileManager.default.fileExists(atPath: configFile),
              FileManager.default.fileExists(atPath: metaFile) else {
            return false
        }

        let desktopConfigPath = "\(dataDir)/claude_desktop_config.json"
        guard let desktopConfig = readJSONDictionary(atPath: desktopConfigPath),
              desktopConfig["deploymentMode"] as? String == "3p" else {
            return false
        }

        return true
    }

    private func readJSONDictionary(atPath path: String) -> [String: Any]? {
        guard FileManager.default.fileExists(atPath: path),
              let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
              let object = try? JSONSerialization.jsonObject(with: data),
              let dict = object as? [String: Any] else {
            return nil
        }
        return dict
    }

    private func writeJSONDictionary(_ dict: [String: Any], toPath path: String) -> Bool {
        do {
            let parent = URL(fileURLWithPath: path).deletingLastPathComponent().path
            try FileManager.default.createDirectory(atPath: parent, withIntermediateDirectories: true, attributes: nil)
            let data = try JSONSerialization.data(withJSONObject: dict, options: .prettyPrinted)
            try data.write(to: URL(fileURLWithPath: path), options: .atomic)
            return true
        } catch {
            addLog("❌ 写入 JSON 失败: \(error.localizedDescription)", type: .error)
            return false
        }
    }

    private func writeDesktopConfig(deploymentMode: String) -> Bool {
        let path = "\(dataDir)/claude_desktop_config.json"
        var config = readJSONDictionary(atPath: path) ?? [:]
        config["deploymentMode"] = deploymentMode
        if config["preferences"] == nil {
            config["preferences"] = [
                "sidebarMode": "task",
                "coworkWebSearchEnabled": true
            ]
        }
        return writeJSONDictionary(config, toPath: path)
    }

    private func writeDeveloperSettings() -> Bool {
        writeJSONDictionary(["allowDevTools": true], toPath: "\(dataDir)/developer_settings.json")
    }

    private func writeBasicConfigIfNeeded() {
        let path = "\(dataDir)/config.json"
        guard !FileManager.default.fileExists(atPath: path) else { return }
        _ = writeJSONDictionary([
            "locale": Locale.current.identifier,
            "userThemeMode": "system"
        ], toPath: path)
    }

    func resetToDefaults() {
        stopProxy()
        try? FileManager.default.removeItem(atPath: configDir)
        profiles = [ConfigProfile.makeDefault()]
        activeProfileId = profiles.first?.id
        proxyPort = 3456
        defaults.set(proxyPort, forKey: proxyPortKey)
        saveProfilesToDefaults()
        saveConfigToDisk()
        addLog("🔄 已恢复默认配置", type: .info)
    }

    // MARK: - Status & Process Management

    func refreshStatus() {
        isClaudeInstalled = FileManager.default.fileExists(atPath: claudeApp)
        let configFile = "\(configDir)/\(configId).json"
        isConfigured = FileManager.default.fileExists(atPath: configFile)
        isDeveloperModeEnabled = detectDeveloperModeEnabled()
        DispatchQueue.global(qos: .background).async {
            self.checkRunningInstance()
            self.checkProxyRunning()
        }
    }

    private func runningInstancePID() -> String {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/bash")
        task.arguments = ["-c", "ps aux | grep 'MacOS/Claude --user-data-dir=\(dataDir)' | grep -v grep | awk '{print $2}' | head -1"]
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = Pipe()
        do {
            try task.run()
            task.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        } catch {
            return ""
        }
    }

    func checkRunningInstance() {
        let pid = runningInstancePID()
        DispatchQueue.main.async {
            self.instancePID = pid
            self.isInstanceRunning = !pid.isEmpty
        }
    }

    func checkProxyRunning() {
        let running: Bool
        if let process = proxyProcess {
            running = process.isRunning
        } else {
            running = false
        }
        // Must publish on main thread to avoid SwiftUI background-thread fault
        if Thread.isMainThread {
            if isProxyRunning != running {
                isProxyRunning = running
            }
        } else {
            DispatchQueue.main.async {
                if self.isProxyRunning != running {
                    self.isProxyRunning = running
                }
            }
        }
    }

    func startInstance() {
        guard isClaudeInstalled else {
            addLog("❌ Claude Desktop 未安装", type: .error)
            return
        }

        guard !isInstanceStarting && !isInstanceStopping else {
            addLog("⚠️ 操作进行中，请稍候", type: .warning)
            return
        }

        if isInstanceRunning {
            addLog("⚠️ 实例已在运行 (PID: \(instancePID))", type: .warning)
            return
        }

        guard isDeveloperModeEnabled else {
            addLog("⚠️ 请先开启开发者模式", type: .warning)
            return
        }

        isInstanceStarting = true

        guard let profile = activeProfile else {
            addLog("⚠️ 没有激活的配置", type: .warning)
            isInstanceStarting = false
            return
        }

        if profile.isCcSwitchMode {
            // CC-Switch mode: skip local proxy, directly configure and launch
            addLog("⏳ 正在启动 (CC-Switch 模式)...", type: .info)
            // Explicitly set proxy state to false in CC-Switch mode
            isProxyRunning = false
            saveConfigToDisk()
            launchClaudeInstance()
        } else {
            // Local proxy mode: start proxy first, then configure and launch
            addLog("⏳ 正在准备启动隔离实例...", type: .info)
            let proxyStarted = startProxy()

            // Small delay for proxy to be ready
            DispatchQueue.main.asyncAfter(deadline: .now() + (proxyStarted ? 1.5 : 0)) {
                if !proxyStarted || !self.isProxyPortReachable(self.proxyPort) {
                    self.isProxyRunning = false
                    self.isInstanceStarting = false
                    self.addLog("❌ 代理端口未监听，已取消启动。请先解决代理端口或 Python 环境问题。", type: .error)
                    return
                }
                self.saveConfigToDisk()
                self.launchClaudeInstance()
            }
        }
    }

    private func launchClaudeInstance() {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        task.arguments = ["-n", "-a", claudeApp, "--args", "--user-data-dir=\(dataDir)"]
        task.standardOutput = Pipe()
        task.standardError = Pipe()
        do {
            try task.run()
            addLog("🚀 正在启动隔离实例...", type: .info)
        } catch {
            addLog("❌ 启动失败: \(error.localizedDescription)", type: .error)
            isInstanceStarting = false
            return
        }

        DispatchQueue.global(qos: .background).asyncAfter(deadline: .now() + 3) {
            let pid = self.runningInstancePID()
            DispatchQueue.main.async {
                self.instancePID = pid
                self.isInstanceRunning = !pid.isEmpty
                self.isInstanceStarting = false
                if !pid.isEmpty {
                    self.addLog("🚀 隔离实例已启动 (PID: \(pid))", type: .success)
                } else {
                    self.addLog("⏳ 实例启动中，请稍候...", type: .info)
                }
            }
        }
    }

    func stopInstance() async {
        guard !isInstanceStarting && !isInstanceStopping else {
            addLog("⚠️ 操作进行中，请稍候", type: .warning)
            return
        }

        guard isInstanceRunning, !instancePID.isEmpty else {
            addLog("⚠️ 没有运行中的实例", type: .warning)
            return
        }

        let savedPID = instancePID
        await MainActor.run {
            isInstanceStopping = true
            addLog("⏹ 正在停止实例 (PID: \(savedPID))...", type: .info)
        }

        // Step 1: Send SIGTERM to main process
        await runCommand("/bin/kill", arguments: [savedPID])

        // Step 2: Wait and cleanup process tree
        try? await Task.sleep(nanoseconds: 2_000_000_000)
        await runCommand("/usr/bin/pkill", arguments: ["-f", "user-data-dir=\(dataDir)"])

        // Step 3: Check for remaining processes
        try? await Task.sleep(nanoseconds: 1_000_000_000)
        let firstCheckPid = await runningInstancePIDAsync()

        // Step 4: Force kill if needed
        var finalPid = firstCheckPid
        if !firstCheckPid.isEmpty {
            let warningPid = firstCheckPid
            await MainActor.run {
                addLog("⚠️ 仍有残留进程 (PID: \(warningPid))，尝试强制终止...", type: .warning)
            }
            await runCommand("/usr/bin/pkill", arguments: ["-9", "-f", "user-data-dir=\(dataDir)"])
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            finalPid = await runningInstancePIDAsync()
        }

        // Step 5: Final state update
        let resultPid = finalPid
        await MainActor.run {
            instancePID = resultPid
            isInstanceRunning = !resultPid.isEmpty
            isInstanceStopping = false
            stopProxy()
            if resultPid.isEmpty {
                addLog("✅ 实例已完全停止", type: .success)
            } else {
                addLog("❌ 仍有进程未能终止 (PID: \(resultPid))", type: .error)
            }
        }
    }

    private func runCommand(_ path: String, arguments: [String]) async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: path)
                process.arguments = arguments
                process.standardOutput = Pipe()
                process.standardError = Pipe()
                try? process.run()
                process.waitUntilExit()
                continuation.resume()
            }
        }
    }

    private func runningInstancePIDAsync() async -> String {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let pid = self.runningInstancePID()
                continuation.resume(returning: pid)
            }
        }
    }

    func openDataDir() {
        try? FileManager.default.createDirectory(atPath: dataDir, withIntermediateDirectories: true, attributes: nil)
        NSWorkspace.shared.open(URL(fileURLWithPath: dataDir))
        addLog("📁 已打开数据目录", type: .info)
    }

    func addLog(_ message: String, type: LogType? = nil) {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        let time = formatter.string(from: Date())

        let logType: LogType
        if let t = type {
            logType = t
        } else {
            if message.hasPrefix("✅") { logType = .success }
            else if message.hasPrefix("❌") { logType = .error }
            else if message.hasPrefix("⚠️") { logType = .warning }
            else { logType = .info }
        }

        DispatchQueue.main.async {
            self.logs.insert(LogEntry(time: time, message: message, type: logType), at: 0)
            if self.logs.count > 100 { self.logs.removeLast() }
        }
    }

    func clearLogs() {
        logs.removeAll()
    }

    func setProxyPort(_ port: Int) {
        proxyPort = port
        defaults.set(port, forKey: proxyPortKey)
    }
}

// MARK: - Content View

struct ContentView: View {
    @StateObject private var manager = ClaudeDualManager()
    @State private var selectedTab: AppTab = .status
    @State private var timer: Timer?
    @AppStorage("appearancePreference") private var appearancePreference = AppAppearance.system.rawValue

    var body: some View {
        HStack(spacing: 0) {
            AppSidebar(selectedTab: $selectedTab, appearancePreference: $appearancePreference, manager: manager)

            Divider()

            Group {
                switch selectedTab {
                case .status:
                    StatusTab(manager: manager)
                case .configuration:
                    ConfigurationTab(manager: manager)
                case .logs:
                    LogsTab(manager: manager)
                case .about:
                    AboutTab()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(AppTheme.canvas)
        }
        .tint(AppTheme.focus)
        .preferredColorScheme(AppAppearance(rawValue: appearancePreference)?.colorScheme)
        .frame(minWidth: 1040, minHeight: 680)
        .onAppear {
            NSLog("[CD] ContentView.onAppear")
            manager.refreshStatus()
            timer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { _ in
                DispatchQueue.global(qos: .background).async {
                    self.manager.checkRunningInstance()
                    self.manager.checkProxyRunning()
                }
            }
        }
        .onDisappear {
            timer?.invalidate()
        }
    }
}

struct AppSidebar: View {
    @Binding var selectedTab: AppTab
    @Binding var appearancePreference: String
    @ObservedObject var manager: ClaudeDualManager

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 11) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 38, height: 38)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

                VStack(alignment: .leading, spacing: 2) {
                    Text("ClaudeDual")
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                    Text("Desktop Console")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.secondary)
                }
            }
            .padding(.horizontal, 18)
            .padding(.top, 20)
            .padding(.bottom, 22)

            Text("工作台")
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(.secondary)
                .textCase(.uppercase)
                .padding(.horizontal, 20)
                .padding(.bottom, 8)

            VStack(spacing: 5) {
                ForEach(AppTab.allCases, id: \.rawValue) { tab in
                    SidebarItem(tab: tab, isSelected: selectedTab == tab) {
                        selectedTab = tab
                    }
                }
            }
            .padding(.horizontal, 10)

            Spacer()

            Menu {
                ForEach(AppAppearance.allCases) { appearance in
                    Button(action: { appearancePreference = appearance.rawValue }) {
                        Label(appearance.title, systemImage: appearancePreference == appearance.rawValue ? "checkmark" : appearance.icon)
                    }
                }
            } label: {
                HStack(spacing: 9) {
                    Image(systemName: currentAppearance.icon)
                        .frame(width: 18)
                    Text("外观")
                        .font(.system(size: 12, weight: .medium))
                    Spacer()
                    Text(currentAppearance.title)
                        .font(.system(size: 10))
                        .foregroundColor(AppTheme.muted)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 8, weight: .semibold))
                        .foregroundColor(AppTheme.muted)
                }
                .padding(.horizontal, 11)
                .frame(height: 34)
                .background(AppTheme.surface.opacity(0.68), in: RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(AppTheme.border, lineWidth: 1))
            }
            .menuStyle(.borderlessButton)
            .padding(.horizontal, 12)
            .padding(.bottom, 4)

            HStack(spacing: 9) {
                Circle()
                    .fill(manager.isInstanceRunning ? AppTheme.success : Color.secondary.opacity(0.45))
                    .frame(width: 8, height: 8)

                VStack(alignment: .leading, spacing: 2) {
                    Text(manager.isInstanceRunning ? "隔离实例运行中" : "隔离实例未运行")
                        .font(.system(size: 11, weight: .semibold))
                    Text(manager.activeProfile?.name ?? "尚未选择配置")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .padding(12)
            .background(AppTheme.surface.opacity(0.56), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 9).stroke(AppTheme.borderSoft, lineWidth: 1))
            .padding(12)
        }
        .frame(width: 216)
        .background(AppTheme.sidebar.opacity(0.88))
    }

    private var currentAppearance: AppAppearance {
        AppAppearance(rawValue: appearancePreference) ?? .system
    }
}

struct SidebarItem: View {
    let tab: AppTab
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: tab.icon)
                    .font(.system(size: 14, weight: .semibold))
                    .frame(width: 22)
                Text(tab.rawValue)
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
            }
            .foregroundColor(isSelected ? AppTheme.accent : AppTheme.ink)
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity, minHeight: 36, maxHeight: 36, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isSelected ? AppTheme.accentSoft : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

struct PageHeader<Trailing: View>: View {
    let eyebrow: String
    let title: String
    let subtitle: String
    @ViewBuilder let trailing: Trailing

    var body: some View {
        HStack(alignment: .center, spacing: 20) {
            VStack(alignment: .leading, spacing: 4) {
                Text(eyebrow)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(AppTheme.accent)
                Text(title)
                    .font(.system(size: 22, weight: .bold))
                Text(subtitle)
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            }
            Spacer()
            trailing
        }
    }
}

// MARK: - Status Tab

struct StatusTab: View {
    @ObservedObject var manager: ClaudeDualManager

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                PageHeader(
                    eyebrow: "工作台",
                    title: "运行概览",
                    subtitle: "查看 Claude Desktop、隔离实例与代理服务的实时状态"
                ) {
                    HStack(spacing: 8) {
                        Button(action: manager.openDataDir) {
                            Label("数据目录", systemImage: "folder")
                        }
                        .buttonStyle(.bordered)

                        Button(action: manager.refreshStatus) {
                            Image(systemName: "arrow.clockwise")
                                .frame(width: 16, height: 16)
                        }
                        .buttonStyle(.bordered)
                        .disabled(manager.isInstanceStarting || manager.isInstanceStopping)
                        .help("刷新状态")
                    }
                }

                DeveloperModeStatusCard(manager: manager)

                HStack(spacing: 12) {
                    StatusCard(
                        title: "Claude Desktop",
                        subtitle: manager.isClaudeInstalled ? "已安装" : "未安装",
                        icon: "macwindow",
                        color: manager.isClaudeInstalled ? AppTheme.success : AppTheme.danger,
                        detail: manager.isClaudeInstalled ? "应用已就绪" : "请先安装应用"
                    )

                    StatusCard(
                        title: "隔离实例",
                        subtitle: instanceStatusText,
                        icon: manager.isInstanceStarting || manager.isInstanceStopping ? "hourglass" : "cpu",
                        color: instanceStatusColor,
                        detail: manager.isInstanceRunning ? "PID \(manager.instancePID)" : "等待启动"
                    )

                    StatusCard(
                        title: "代理服务",
                        subtitle: proxyStatusText,
                        icon: "arrow.triangle.2.circlepath",
                        color: proxyStatusColor,
                        detail: proxyDetail
                    )
                }

                if let profile = manager.activeProfile {
                    ActiveProfileCard(
                        profile: profile,
                        manager: manager,
                        instanceStatusText: instanceStatusText,
                        instanceStatusColor: instanceStatusColor
                    )
                }
            }
            .padding(28)
        }
    }

    private var instanceStatusText: String {
        if manager.isInstanceStarting { return "启动中" }
        if manager.isInstanceStopping { return "停止中" }
        return manager.isInstanceRunning ? "运行中" : "未运行"
    }

    private var instanceStatusColor: Color {
        if manager.isInstanceStarting || manager.isInstanceStopping { return AppTheme.warning }
        return manager.isInstanceRunning ? AppTheme.success : Color.secondary
    }

    private var proxyStatusText: String {
        if manager.activeProfile?.isCcSwitchMode == true { return "CC-Switch" }
        return manager.isProxyRunning ? "运行中" : "未运行"
    }

    private var proxyStatusColor: Color {
        if manager.activeProfile?.isCcSwitchMode == true { return AppTheme.info }
        return manager.isProxyRunning ? AppTheme.success : Color.secondary
    }

    private var proxyDetail: String {
        if let profile = manager.activeProfile, profile.isCcSwitchMode {
            return profile.effectiveCcSwitchUrl
        }
        return "本地端口 \(manager.proxyPort)"
    }
}

// MARK: - Active Profile Card

struct ActiveProfileCard: View {
    let profile: ConfigProfile
    @ObservedObject var manager: ClaudeDualManager
    let instanceStatusText: String
    let instanceStatusColor: Color

    var body: some View {
        HStack(alignment: .center, spacing: 22) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 9) {
                    Image(systemName: "checkmark.shield.fill")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(AppTheme.accent)
                    Text("当前配置")
                        .font(.system(size: 15, weight: .bold))
                    Text(instanceStatusText)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(instanceStatusColor)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(instanceStatusColor.opacity(0.14), in: Capsule())
                }

                HStack(alignment: .top, spacing: 24) {
                    ProfileInfoBlock(label: "配置名称", value: profile.name)
                    ProfileInfoBlock(label: "代理模式", value: profile.isCcSwitchMode ? "CC Switch" : "本地代理")
                    ProfileInfoBlock(
                        label: profile.isCcSwitchMode ? "网关地址" : "上游模型",
                        value: profile.isCcSwitchMode ? profile.effectiveCcSwitchUrl : profile.effectiveUpstreamModel
                    )
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Divider()
                .frame(height: 72)

            primaryAction
        }
        .padding(20)
        .appCard(borderColor: AppTheme.accent.opacity(0.18))
    }

    @ViewBuilder
    private var primaryAction: some View {
        if manager.isInstanceRunning || manager.isInstanceStopping {
            CompactActionButton(
                title: manager.isInstanceStopping ? "停止中" : "停止",
                icon: manager.isInstanceStopping ? "hourglass" : "stop.fill",
                color: AppTheme.danger,
                isDestructive: true,
                isLoading: manager.isInstanceStopping,
                disabled: !manager.isInstanceRunning || manager.isInstanceStarting || manager.isInstanceStopping
            ) {
                Task { await manager.stopInstance() }
            }
        } else {
            CompactActionButton(
                title: manager.isInstanceStarting ? "启动中" : "启动",
                icon: manager.isInstanceStarting ? "hourglass" : "play.fill",
                color: AppTheme.ink,
                isLoading: manager.isInstanceStarting,
                disabled: manager.isInstanceStarting || manager.isInstanceStopping || !manager.isClaudeInstalled || !manager.isDeveloperModeEnabled
            ) {
                manager.startInstance()
            }
        }
    }

}

struct ProfileInfoBlock: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(.secondary)
            Text(value)
                .font(.system(size: 12, weight: .semibold))
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct CompactActionButton: View {
    let title: String
    let icon: String
    let color: Color
    var isDestructive: Bool = false
    var isLoading: Bool = false
    var disabled: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 9) {
                if isLoading {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Image(systemName: icon)
                        .font(.system(size: 20, weight: .semibold))
                }
                Text(title)
                    .font(.system(size: 14, weight: .bold))
            }
            .foregroundColor(isDestructive ? color : AppTheme.surface)
            .frame(width: 122, height: 46)
            .background(
                isDestructive ? color.opacity(disabled ? 0.04 : 0.08) : color.opacity(disabled ? 0.38 : 1),
                in: RoundedRectangle(cornerRadius: 8, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isDestructive ? color.opacity(disabled ? 0.12 : 0.34) : Color.clear, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .disabled(disabled)
    }
}

// MARK: - Status Card

struct StatusCard: View {
    let title: String
    let subtitle: String
    let icon: String
    let color: Color
    var detail: String? = nil

    var body: some View {
        HStack(spacing: 13) {
            ZStack {
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(color.opacity(0.12))
                Image(systemName: icon)
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundColor(color)
            }
            .frame(width: 44, height: 44)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.secondary)
                Text(subtitle)
                    .font(.system(size: 14, weight: .bold))
                if let detail = detail {
                    Text(detail)
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            Spacer(minLength: 0)
            Circle()
                .fill(color)
                .frame(width: 7, height: 7)
        }
        .padding(15)
        .frame(maxWidth: .infinity, minHeight: 78)
        .appCard(cornerRadius: 10, borderColor: AppTheme.border)
    }
}

struct DeveloperModeStatusCard: View {
    @ObservedObject var manager: ClaudeDualManager

    private var statusColor: Color {
        manager.isDeveloperModeEnabled ? AppTheme.success : AppTheme.warning
    }

    var body: some View {
        HStack(spacing: 16) {
            ZStack {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(statusColor.opacity(0.12))
                Image(systemName: manager.isDeveloperModeEnabled ? "checkmark.shield.fill" : "hammer.fill")
                    .font(.system(size: 23, weight: .semibold))
                    .foregroundColor(statusColor)
            }
            .frame(width: 54, height: 54)

            VStack(alignment: .leading, spacing: 5) {
                Text("开发者模式")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.secondary)
                Text(manager.isDeveloperModeEnabled ? "环境已就绪" : "需要初始化")
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                Text(manager.isConfigured ? "第三方模型配置已就绪，可直接启动隔离实例" : "创建隔离数据目录并初始化网关配置")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }

            Spacer()

            Button(action: manager.enableDeveloperMode) {
                Label(manager.isDeveloperModeEnabled ? "已开启" : "一键开启", systemImage: manager.isDeveloperModeEnabled ? "checkmark" : "power")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(.white)
                    .frame(width: 120, height: 40)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(manager.isDeveloperModeEnabled ? statusColor.opacity(0.68) : AppTheme.ink)
                    )
            }
            .buttonStyle(.plain)
            .disabled(manager.isDeveloperModeEnabled || manager.isInstanceStarting || manager.isInstanceStopping)
        }
        .padding(18)
        .appCard(borderColor: AppTheme.border)
    }
}

// MARK: - Action Button

struct ActionButton: View {
    let title: String
    let icon: String
    let color: Color
    var isSecondary: Bool = false
    var isLoading: Bool = false
    var disabled: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                if !isSecondary {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(disabled ? color.opacity(0.4) : color)
                } else {
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(disabled ? color.opacity(0.2) : color.opacity(0.5), lineWidth: 1)
                        .background(Color.clear)
                }
                HStack(spacing: 8) {
                    if isLoading {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Image(systemName: icon)
                    }
                    Text(title)
                }
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(isSecondary ? (disabled ? color.opacity(0.4) : color) : .white)
            }
            .frame(maxWidth: .infinity, minHeight: 28)
        }
        .buttonStyle(.plain)
        .disabled(disabled)
    }
}

// MARK: - Configuration Tab

struct ConfigurationTab: View {
    @ObservedObject var manager: ClaudeDualManager
    @State private var selectedProfileId: UUID?
    @State private var isNewProfile = false

    var selectedProfile: ConfigProfile? {
        manager.profiles.first { $0.id == selectedProfileId }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            PageHeader(
                eyebrow: "配置管理",
                title: "推理配置",
                subtitle: "管理模型网关、认证方式与代理连接"
            ) {
                Button(action: {
                    isNewProfile = true
                    selectedProfileId = nil
                }) {
                    Label("新建配置", systemImage: "plus")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(AppTheme.surface)
                        .padding(.horizontal, 13)
                        .frame(height: 32)
                        .background(AppTheme.ink, in: RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
            }

            HStack(spacing: 0) {
            // Left: Profile List
            VStack(spacing: 0) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("配置列表")
                            .font(.system(size: 13, weight: .bold))
                        Text("\(manager.profiles.count) 个配置")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    Button(action: {
                        isNewProfile = true
                        selectedProfileId = nil
                    }) {
                        Image(systemName: "plus")
                            .font(.system(size: 11, weight: .bold))
                            .frame(width: 26, height: 26)
                            .background(AppTheme.accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 7))
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(AppTheme.accent)
                    .help("新建配置")
                }
                .padding(14)

                Divider()

                ScrollView {
                    LazyVStack(spacing: 6) {
                        ForEach(manager.profiles) { profile in
                            ProfileRow(
                                profile: profile,
                                isActive: manager.activeProfileId == profile.id,
                                isSelected: selectedProfileId == profile.id
                            )
                            .contentShape(Rectangle())
                            .onTapGesture {
                                isNewProfile = false
                                selectedProfileId = profile.id
                            }
                            .contextMenu {
                                Button("设为当前配置") {
                                    manager.activateProfile(id: profile.id)
                                }
                                Button("复制配置") {
                                    manager.duplicateProfile(id: profile.id)
                                }
                                Divider()
                                Button("删除") {
                                    manager.deleteProfile(id: profile.id)
                                    if selectedProfileId == profile.id {
                                        selectedProfileId = manager.profiles.first?.id
                                    }
                                }
                                .disabled(manager.profiles.count <= 1)
                            }
                        }
                    }
                    .padding(9)
                }
            }
            .frame(width: 210)
            .background(AppTheme.surface.opacity(0.48))

            Divider()

            // Right: Profile Editor
            if isNewProfile {
                ProfileEditor(
                    manager: manager,
                    profile: nil,
                    onSave: { newProfile in
                        let profile = manager.addProfile(
                            name: newProfile.name,
                            apiBaseUrl: newProfile.apiBaseUrl,
                            apiKey: newProfile.apiKey,
                            authScheme: newProfile.effectiveAuthScheme,
                            modelName: newProfile.modelName,
                            allowedHosts: newProfile.allowedHosts
                        )
                        manager.activateProfile(id: profile.id)
                        isNewProfile = false
                        selectedProfileId = profile.id
                    },
                    onCancel: {
                        isNewProfile = false
                        selectedProfileId = manager.profiles.first?.id
                    }
                )
                .id("new-profile")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let profile = selectedProfile {
                ProfileEditor(
                    manager: manager,
                    profile: profile,
                    onSave: { updated in
                        manager.updateProfile(
                            id: profile.id,
                            name: updated.name,
                            apiBaseUrl: updated.apiBaseUrl,
                            apiKey: updated.apiKey,
                            authScheme: updated.effectiveAuthScheme,
                            modelName: updated.modelName,
                            allowedHosts: updated.allowedHosts,
                            proxyMode: updated.proxyMode,
                            ccSwitchUrl: updated.ccSwitchUrl
                        )
                    },
                    onCancel: nil
                )
                .id(profile.id)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                VStack {
                    Spacer()
                    Text("选择或创建一个配置")
                        .foregroundColor(.secondary)
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            }
            .appCard(cornerRadius: 10)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .padding(28)
        .onAppear {
            if selectedProfileId == nil && !isNewProfile {
                selectedProfileId = manager.activeProfileId ?? manager.profiles.first?.id
            }
        }
    }
}

// MARK: - Profile Row

struct ProfileRow: View {
    let profile: ConfigProfile
    let isActive: Bool
    let isSelected: Bool

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(isSelected ? AppTheme.accent.opacity(0.11) : Color.clear)
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(isSelected ? AppTheme.accent.opacity(0.28) : Color.clear, lineWidth: 1)

            HStack(spacing: 10) {
                ZStack {
                    Circle()
                        .fill(isActive ? AppTheme.success.opacity(0.14) : Color.secondary.opacity(0.09))
                    Image(systemName: isActive ? "checkmark" : "network")
                        .foregroundColor(isActive ? AppTheme.success : .secondary)
                        .font(.system(size: 10, weight: .bold))
                }
                .frame(width: 28, height: 28)

                VStack(alignment: .leading, spacing: 3) {
                    Text(profile.name)
                        .font(.system(size: 12, weight: .semibold))
                    Text(profile.isCcSwitchMode ? "CC Switch" : profile.effectiveUpstreamModel)
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }

                Spacer()

                if isSelected {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(AppTheme.accent)
                }
            }
            .padding(.vertical, 9)
            .padding(.horizontal, 10)
        }
    }
}

// MARK: - Profile Editor

struct ProfileEditor: View {
    @ObservedObject var manager: ClaudeDualManager
    let profile: ConfigProfile?
    let onSave: (ConfigProfile) -> Void
    let onCancel: (() -> Void)?

    @State private var name: String = ""
    @State private var apiBaseUrl: String = ""
    @State private var apiKey: String = ""
    @State private var authScheme: String = "bearer"
    @State private var modelName: String = ""
    @State private var allowedHosts: String = ""
    @State private var proxyPort: String = ""
    @State private var showApiKey = false
    @State private var proxyMode: String = "localProxy"
    @State private var ccSwitchUrl: String = ConfigProfile.defaultCcSwitchUrl

    var isNew: Bool { profile == nil }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(isNew ? "新建配置" : "编辑配置")
                                .font(.system(size: 18, weight: .bold, design: .rounded))
                            Text(isNew ? "填写连接信息并创建新的推理环境" : "修改当前配置的网关与认证参数")
                                .font(.system(size: 10))
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        if let cancel = onCancel {
                            Button("取消", action: cancel)
                                .buttonStyle(.plain)
                                .foregroundColor(.secondary)
                        }
                    }

                    connectionSettings
                }
                .padding(20)
            }

            Divider()

            actionBar
                .padding(.horizontal, 20)
                .padding(.vertical, 14)
                .background(AppTheme.surfaceSoft)
        }
        .onAppear {
            NSLog("[CD] ProfileEditor.onAppear, isNew=\(isNew)")
            loadProfile()
        }
        .onChange(of: profile?.id) { _ in
            loadProfile()
        }
        .onChange(of: manager.proxyPort) { newPort in
            proxyPort = String(newPort)
        }
    }

    private var connectionSettings: some View {
        VStack(alignment: .leading, spacing: 15) {
            Label("连接设置", systemImage: "network")
                .font(.system(size: 13, weight: .semibold))

            Divider()

            ConfigField(title: "配置名称", prompt: "如：Coding Plan", text: $name)

            VStack(alignment: .leading, spacing: 6) {
                fieldLabel("代理模式")
                Picker("", selection: $proxyMode) {
                    Text("本地代理").tag("localProxy")
                    Text("CC Switch").tag("ccSwitch")
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }

            modeFields
            ConfigField(title: "出站主机白名单", prompt: "* 表示允许所有，多个用逗号分隔", text: $allowedHosts)
        }
        .padding(15)
        .background(AppTheme.surfaceSoft, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(AppTheme.border, lineWidth: 1))
    }

    @ViewBuilder
    private var modeFields: some View {
        if proxyMode == "ccSwitch" {
            ConfigField(title: "CC Switch 地址", prompt: "http://127.0.0.1:15721", text: $ccSwitchUrl)
            Text("模型映射和认证在 CC Switch 中配置，此处只需填写地址。Model ID 须为 Anthropic 风格（如 claude-opus-4-7）。")
                .font(.system(size: 11))
                .foregroundColor(AppTheme.muted)
        } else {
            ConfigField(title: "API Base URL", prompt: "https://coding.dashscope.aliyuncs.com/apps/anthropic", text: $apiBaseUrl)
            apiKeyField
            authSchemeField
            ConfigField(title: "上游模型名称", prompt: ConfigProfile.defaultUpstreamModel, text: $modelName)
            proxyPortField
        }
    }

    private var apiKeyField: some View {
        VStack(alignment: .leading, spacing: 6) {
            fieldLabel("API Key")
            HStack {
                Group {
                    if showApiKey {
                        TextField("sk-...", text: $apiKey)
                    } else {
                        SecureField("sk-...", text: $apiKey)
                    }
                }
                .textFieldStyle(.roundedBorder)

                Button(action: { showApiKey.toggle() }) {
                    Image(systemName: showApiKey ? "eye.slash" : "eye")
                        .foregroundColor(AppTheme.muted)
                        .frame(width: 24, height: 24)
                }
                .buttonStyle(.plain)
                .help(showApiKey ? "隐藏 API Key" : "显示 API Key")
            }
        }
    }

    private var authSchemeField: some View {
        VStack(alignment: .leading, spacing: 6) {
            fieldLabel("上游认证方式")
            Picker("", selection: $authScheme) {
                Text("Bearer").tag("bearer")
                Text("x-api-key").tag("x-api-key")
                Text("anthropic-api-key").tag("anthropic-api-key")
            }
            .pickerStyle(.segmented)
            .labelsHidden()
        }
    }

    private var proxyPortField: some View {
        VStack(alignment: .leading, spacing: 6) {
            fieldLabel("代理端口（全局）")
            HStack {
                TextField("3456", text: $proxyPort)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 100)
                Text("本地代理监听端口，用于透传请求并映射模型")
                    .font(.system(size: 11))
                    .foregroundColor(AppTheme.muted)
                Spacer()
            }
        }
    }

    private func fieldLabel(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 11, weight: .medium))
            .foregroundColor(AppTheme.inkSecondary)
    }

    private var actionBar: some View {
        HStack(spacing: 10) {
            Button(action: save) {
                Label(isNew ? "创建并激活" : "保存配置", systemImage: "checkmark")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(AppTheme.surface)
                    .frame(maxWidth: .infinity, minHeight: 32)
                    .background(AppTheme.ink, in: RoundedRectangle(cornerRadius: 8))
            }
            .buttonStyle(.plain)

            if !isNew, let profile = profile {
                profileActions(profile)
            }
        }
    }

    private func profileActions(_ profile: ConfigProfile) -> some View {
        let isCurrent = manager.activeProfileId == profile.id
        return HStack(spacing: 10) {
            Button(action: { manager.activateProfile(id: profile.id) }) {
                Label(isCurrent ? "当前配置" : "设为当前", systemImage: isCurrent ? "checkmark.circle.fill" : "arrow.left.arrow.right.circle")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(isCurrent ? AppTheme.muted : AppTheme.ink)
                    .padding(.horizontal, 12)
                    .frame(minHeight: 32)
                    .background(AppTheme.surface, in: RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(AppTheme.border, lineWidth: 1))
            }
            .buttonStyle(.plain)
            .disabled(isCurrent)

            Button(action: { manager.duplicateProfile(id: profile.id) }) {
                Label("复制", systemImage: "doc.on.doc")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(AppTheme.inkSecondary)
                    .frame(minHeight: 32)
            }
            .buttonStyle(.plain)

            Button(action: { manager.deleteProfile(id: profile.id) }) {
                Label("删除", systemImage: "trash")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(AppTheme.danger)
                    .frame(minHeight: 32)
            }
            .buttonStyle(.plain)
            .disabled(manager.profiles.count <= 1)
        }
    }

    private func loadProfile() {
        if let p = profile {
            name = p.name
            apiBaseUrl = p.effectiveApiBaseUrl
            apiKey = p.effectiveApiKey
            authScheme = p.effectiveAuthScheme
            modelName = p.effectiveUpstreamModel
            allowedHosts = p.allowedHosts
            proxyMode = p.effectiveProxyMode
            ccSwitchUrl = p.effectiveCcSwitchUrl
        } else {
            name = ""
            apiBaseUrl = ""
            apiKey = ""
            authScheme = "bearer"
            modelName = ConfigProfile.defaultUpstreamModel
            allowedHosts = "*"
            proxyMode = "localProxy"
            ccSwitchUrl = ConfigProfile.defaultCcSwitchUrl
        }
        proxyPort = String(manager.proxyPort)
    }

    private func save() {
        // Update global proxy port if changed (only relevant for localProxy mode)
        if proxyMode == "localProxy", let newPort = Int(proxyPort), newPort > 1024 && newPort < 65535, newPort != manager.proxyPort {
            manager.setProxyPort(newPort)
        }

        let updated = ConfigProfile(
            id: profile?.id ?? UUID(),
            name: name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "未命名配置" : name.trimmingCharacters(in: .whitespacesAndNewlines),
            apiBaseUrl: apiBaseUrl.trimmingCharacters(in: .whitespacesAndNewlines),
            apiKey: apiKey.trimmingCharacters(in: .whitespacesAndNewlines),
            authScheme: authScheme,
            modelName: modelName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? ConfigProfile.defaultUpstreamModel : modelName,
            allowedHosts: allowedHosts.trimmingCharacters(in: .whitespacesAndNewlines),
            proxyMode: proxyMode,
            ccSwitchUrl: ccSwitchUrl.trimmingCharacters(in: .whitespacesAndNewlines)
        )
        onSave(updated)
    }
}

// MARK: - Config Field

struct ConfigField: View {
    let title: String
    let prompt: String
    @Binding var text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(AppTheme.inkSecondary)
            TextField(prompt, text: $text)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 12))
                .controlSize(.large)
        }
    }
}

// MARK: - Info Row

struct InfoRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack(alignment: .top) {
            Text(label + ":")
                .foregroundColor(.secondary)
                .frame(width: 80, alignment: .trailing)
            Text(value)
                .font(.system(.body, design: .monospaced))
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer()
        }
        .font(.system(size: 12))
    }
}

// MARK: - About Tab

struct AboutTab: View {
    private let authorURL = URL(string: "https://www.xiaohongshu.com/user/profile/588f4a595e87e7481d7b0c75")!
    private let appVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
    private let buildNumber = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
    private let releaseTime = Bundle.main.object(forInfoDictionaryKey: "ClaudeDualReleaseTime") as? String ?? "-"

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                PageHeader(
                    eyebrow: "应用信息",
                    title: "关于 ClaudeDual",
                    subtitle: "为 Claude Desktop 打造的第三方模型与开发者模式管理工具"
                ) {
                    EmptyView()
                }

                VStack(spacing: 18) {
                    ZStack {
                        Circle()
                            .fill(AppTheme.accent.opacity(0.10))
                            .frame(width: 112, height: 112)
                        Image(nsImage: NSApp.applicationIconImage)
                            .resizable()
                            .frame(width: 78, height: 78)
                            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }

                    VStack(spacing: 6) {
                        Text("ClaudeDual")
                            .font(.system(size: 26, weight: .bold, design: .rounded))
                        Text("让 Claude Desktop 自由连接你的模型服务")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                    }

                    VStack(spacing: 0) {
                    AboutInfoRow(label: "版本", value: "\(appVersion) (\(buildNumber))")
                    Divider()
                    AboutInfoRow(label: "发布时间", value: releaseTime)
                    Divider()
                    AboutInfoRow(label: "作者", value: "赛脖古")
                    Divider()
                    AboutInfoRow(label: "数据目录", value: "~/Library/Application Support/ClaudeDual-3p")
                    Divider()
                    HStack {
                        Text("小红书")
                            .foregroundColor(.secondary)
                            .frame(width: 86, alignment: .leading)
                        Link("赛脖古主页", destination: authorURL)
                            .foregroundColor(AppTheme.focus)
                        Spacer()
                        Image(systemName: "arrow.up.right")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(.secondary)
                    }
                    .font(.system(size: 13))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 11)
                }
                    .appCard(cornerRadius: 10)
                    .frame(maxWidth: 520)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
            }
            .padding(28)
        }
    }
}

struct AboutInfoRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .foregroundColor(.secondary)
                .frame(width: 86, alignment: .leading)
            Text(value)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer()
        }
        .font(.system(size: 13))
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}

// MARK: - Logs Tab

struct LogsTab: View {
    @ObservedObject var manager: ClaudeDualManager

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            PageHeader(
                eyebrow: "运行记录",
                title: "运行日志",
                subtitle: "追踪实例启动、配置写入与代理服务事件"
            ) {
                HStack(spacing: 9) {
                    Text("\(manager.logs.count) 条记录")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(AppTheme.surface, in: Capsule())

                    Button(action: manager.clearLogs) {
                        Label("清空", systemImage: "trash")
                    }
                    .buttonStyle(.bordered)
                    .disabled(manager.logs.isEmpty)
                }
            }

            if manager.logs.isEmpty {
                VStack(spacing: 12) {
                    ZStack {
                        Circle()
                            .fill(AppTheme.accent.opacity(0.08))
                        Image(systemName: "text.page.badge.magnifyingglass")
                            .font(.system(size: 25, weight: .medium))
                            .foregroundColor(AppTheme.accent.opacity(0.72))
                    }
                    .frame(width: 62, height: 62)

                    Text("暂无运行日志")
                        .font(.system(size: 15, weight: .semibold))
                    Text("启动实例或修改配置后，相关事件会显示在这里")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .appCard()
            } else {
                ScrollView {
                    LazyVStack(spacing: 7) {
                        ForEach(Array(manager.logs.enumerated()), id: \.element.id) { index, entry in
                            LogRow(entry: entry, index: index)
                        }
                    }
                    .padding(10)
                }
                .appCard()
            }
        }
        .padding(28)
    }
}

struct LogRow: View {
    let entry: LogEntry
    let index: Int

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                Circle()
                    .fill(entry.type.color.opacity(0.12))
                Image(systemName: entry.type.icon)
                    .foregroundColor(entry.type.color)
                    .font(.system(size: 11, weight: .semibold))
            }
            .frame(width: 28, height: 28)

            Text(entry.time)
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundColor(.secondary)
                .frame(width: 58, alignment: .leading)
                .padding(.top, 7)

            Text(entry.message)
                .font(.system(size: 12, weight: .medium))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 5)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(index.isMultiple(of: 2) ? AppTheme.accent.opacity(0.035) : Color.clear, in: RoundedRectangle(cornerRadius: 10))
    }
}
