import SwiftUI
import AppKit
import CryptoKit
import Darwin
import Security

enum ManagedClient: String, Codable, CaseIterable, Identifiable {
    case claude
    case codex

    var id: String { rawValue }

    var title: String {
        switch self {
        case .claude: return "Claude"
        case .codex: return "Codex"
        }
    }

    var desktopTitle: String {
        switch self {
        case .claude: return "Claude Desktop"
        case .codex: return "Codex Desktop"
        }
    }

    var icon: String {
        switch self {
        case .claude: return "sparkles"
        case .codex: return "chevron.left.forwardslash.chevron.right"
        }
    }
}

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
    // Keep the legacy apiBaseUrl for backwards-compatible decoding. New
    // profiles store the protocol-specific endpoints separately.
    var claudeApiBaseUrl: String? = nil
    var codexApiBaseUrl: String? = nil
    // Kept only so profiles written by the short-lived split configuration build still decode.
    // Configuration profiles are shared by Claude and Codex.
    var client: ManagedClient? = nil

    static let defaultUpstreamModel = "provider-default-model"
    static let defaultCcSwitchUrl = "http://127.0.0.1:15721"
    static let defaultInferenceModels = [
        "claude-fable-5",
        "claude-opus-5",
        "claude-sonnet-5",
        "claude-haiku-4-5-20251001"
    ]

    static func makeDefault() -> ConfigProfile {
        ConfigProfile(
            id: UUID(),
            name: "Default Gateway",
            apiBaseUrl: "https://coding.dashscope.aliyuncs.com/apps/anthropic",
            apiKey: "",
            authScheme: "bearer",
            modelName: defaultUpstreamModel,
            allowedHosts: "*",
            claudeApiBaseUrl: "https://coding.dashscope.aliyuncs.com/apps/anthropic",
            codexApiBaseUrl: "https://coding.dashscope.aliyuncs.com/v1"
        )
    }

    var effectiveAuthScheme: String {
        authScheme ?? "bearer"
    }

    var effectiveApiBaseUrl: String {
        apiBaseUrl.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // Claude sends Anthropic Messages requests, while Codex sends OpenAI
    // Responses requests. Alibaba exposes both protocols under different
    // paths, so keep the profile's entered URL but select the protocol-specific
    // endpoint at launch time.
    var effectiveClaudeApiBaseUrl: String {
        let explicit = claudeApiBaseUrl?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !explicit.isEmpty { return explicit }
        return Self.alibabaBaseUrl(effectiveApiBaseUrl, transport: .anthropic)
    }

    var effectiveCodexApiBaseUrl: String {
        let explicit = codexApiBaseUrl?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !explicit.isEmpty { return explicit }
        return effectiveApiBaseUrl
    }

    private enum AlibabaProtocol {
        case anthropic
        case openAI
    }

    private static func alibabaBaseUrl(_ rawValue: String, transport: AlibabaProtocol) -> String {
        guard var components = URLComponents(string: rawValue),
              let host = components.host?.lowercased(),
              host.hasSuffix("aliyuncs.com"),
              !host.isEmpty else {
            return rawValue
        }

        let path = components.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard path == "v1" || path == "compatible-mode/v1" || path == "apps/anthropic" else {
            return rawValue
        }

        switch transport {
        case .anthropic:
            guard path == "v1" || path == "compatible-mode/v1" else { return rawValue }
            components.path = "/apps/anthropic"
        case .openAI:
            guard path == "apps/anthropic" else { return rawValue }
            let isCodingPlanHost = host == "coding.dashscope.aliyuncs.com"
            components.path = isCodingPlanHost ? "/v1" : "/compatible-mode/v1"
        }

        return components.string ?? rawValue
    }

    var effectiveApiKey: String {
        apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var effectiveUpstreamModel: String {
        let trimmed = modelName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { return trimmed }
        return Self.defaultUpstreamModel
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

    var isDirectMode: Bool {
        effectiveProxyMode == "direct"
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
    let client: ManagedClient
}

// MARK: - GitHub Release Updates

private struct GitHubReleaseResponse: Decodable {
    let tagName: String
    let name: String?
    let body: String?
    let htmlURL: URL
    let publishedAt: Date?
    let assets: [GitHubReleaseAsset]

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case name, body, assets
        case htmlURL = "html_url"
        case publishedAt = "published_at"
    }
}

private struct GitHubReleaseAsset: Decodable {
    let name: String
    let browserDownloadURL: URL
    let size: Int64
    let digest: String?

    enum CodingKeys: String, CodingKey {
        case name, size, digest
        case browserDownloadURL = "browser_download_url"
    }
}

private struct AppUpdateManifest: Decodable {
    let version: String
    let tagName: String
    let title: String
    let notes: String
    let publishedAt: Date?
    let releaseURL: URL
    let asset: Asset

    struct Asset: Decodable {
        let name: String
        let url: URL
        let size: Int64
        let sha256: String
    }

    enum CodingKeys: String, CodingKey {
        case version, title, notes, asset
        case tagName = "tag_name"
        case publishedAt = "published_at"
        case releaseURL = "release_url"
    }
}

struct AppUpdateRelease: Identifiable {
    let tagName: String
    let version: String
    let title: String
    let notes: String
    let releaseURL: URL
    let publishedAt: Date?
    fileprivate let asset: GitHubReleaseAsset

    var id: String { tagName }
}

private struct AppSemanticVersion: Comparable {
    let components: [Int]

    init?(_ rawValue: String) {
        var value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.lowercased().hasPrefix("v") {
            value.removeFirst()
        }
        value = String(value.split(separator: "-", maxSplits: 1).first ?? "")
        let parts = value.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count >= 2,
              parts.allSatisfy({ !$0.isEmpty && $0.allSatisfy(\.isNumber) }) else {
            return nil
        }
        components = parts.compactMap { Int($0) }
        guard components.count == parts.count else { return nil }
    }

    static func < (lhs: AppSemanticVersion, rhs: AppSemanticVersion) -> Bool {
        let count = max(lhs.components.count, rhs.components.count)
        for index in 0..<count {
            let left = index < lhs.components.count ? lhs.components[index] : 0
            let right = index < rhs.components.count ? rhs.components[index] : 0
            if left != right { return left < right }
        }
        return false
    }
}

private enum AppUpdateError: LocalizedError {
    case invalidResponse
    case server(Int)
    case invalidRelease
    case missingInstaller
    case untrustedDownloadURL
    case missingDigest
    case invalidDigest
    case sizeMismatch(expected: Int64, actual: Int64)
    case checksumMismatch
    case cannotOpenInstaller
    case mountFailed(String)
    case installerAppMissing
    case destinationNotWritable(String)
    case installFailed(String)

    var errorDescription: String? {
        switch self {
        case .invalidResponse: return "GitHub 返回了无法识别的响应。"
        case .server(let status): return "GitHub Release 请求失败（HTTP \(status)）。"
        case .invalidRelease: return "Release 版本号格式无效。"
        case .missingInstaller: return "最新 Release 中没有找到 DMG 安装包。"
        case .untrustedDownloadURL: return "Release 安装包地址不属于当前 GitHub 仓库。"
        case .missingDigest: return "Release 安装包缺少 SHA-256 摘要，已拒绝下载。"
        case .invalidDigest: return "Release 安装包的 SHA-256 摘要格式无效。"
        case .sizeMismatch(let expected, let actual):
            return "安装包大小不匹配（预期 \(expected) 字节，实际 \(actual) 字节）。"
        case .checksumMismatch: return "安装包 SHA-256 校验失败，文件可能不完整。"
        case .cannotOpenInstaller: return "安装包已下载，但无法自动打开。"
        case .mountFailed(let detail): return "无法挂载安装包：\(detail)"
        case .installerAppMissing: return "安装包中没有找到应用程序。"
        case .destinationNotWritable(let path): return "没有写入权限：\(path)"
        case .installFailed(let detail): return "自动安装失败：\(detail)"
        }
    }
}

@MainActor
final class AppUpdateManager: ObservableObject {
    @Published private(set) var isChecking = false
    @Published private(set) var isDownloading = false
    @Published private(set) var isInstalling = false
    @Published private(set) var availableRelease: AppUpdateRelease?
    @Published private(set) var latestRelease: AppUpdateRelease?
    @Published private(set) var downloadedInstallerURL: URL?
    @Published private(set) var statusMessage = "尚未检查更新"
    @Published private(set) var errorMessage: String?

    let currentVersion: String

    private let latestManifest = URL(string: "https://github.com/saibogoo/ClaudeDual/releases/latest/download/latest.json")!
    private let releasesAPI = URL(string: "https://api.github.com/repos/saibogoo/ClaudeDual/releases/latest")!
    private let releasesPage = URL(string: "https://github.com/saibogoo/ClaudeDual/releases")!
    private let latestReleasePage = URL(string: "https://github.com/saibogoo/ClaudeDual/releases/latest")!
    private let trustedDownloadPathPrefix = "/saibogoo/ClaudeDual/releases/download/"

    init(bundle: Bundle = .main) {
        currentVersion = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0.0"
    }

    @discardableResult
    func checkForUpdates() async -> Bool {
        guard !isChecking else { return availableRelease != nil }
        isChecking = true
        errorMessage = nil
        statusMessage = "正在检查 GitHub Release…"
        defer { isChecking = false }

        do {
            let release = try await loadLatestRelease()
            guard let remoteVersion = AppSemanticVersion(release.tagName),
                  let installedVersion = AppSemanticVersion(currentVersion) else {
                throw AppUpdateError.invalidRelease
            }

            latestRelease = release
            if installedVersion < remoteVersion {
                availableRelease = release
                statusMessage = "发现新版本 \(release.tagName)"
                return true
            }

            availableRelease = nil
            statusMessage = "当前已是最新版本（v\(currentVersion)）"
            return false
        } catch {
            if let remoteTag = try? await loadLatestTagFromReleasePage(),
               let remoteVersion = AppSemanticVersion(remoteTag),
               let installedVersion = AppSemanticVersion(currentVersion) {
                availableRelease = nil
                if remoteVersion <= installedVersion {
                    errorMessage = nil
                    statusMessage = "当前已是最新版本（v\(currentVersion)）"
                    return false
                }
                errorMessage = "发现新版本 \(remoteTag)，但在线升级清单暂不可用，请打开 GitHub Release 手动升级。"
                statusMessage = "发现新版本 \(remoteTag)"
                return false
            }
            let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            errorMessage = message
            statusMessage = "检查更新失败"
            return false
        }
    }

    func downloadAvailableUpdate() async {
        guard let release = availableRelease, !isDownloading else { return }
        isDownloading = true
        errorMessage = nil
        downloadedInstallerURL = nil
        statusMessage = "正在下载 \(release.asset.name)…"
        defer { isDownloading = false }

        do {
            try validate(asset: release.asset)
            var request = URLRequest(url: release.asset.browserDownloadURL)
            request.timeoutInterval = 120
            request.setValue("ClaudexDual/\(currentVersion)", forHTTPHeaderField: "User-Agent")
            let (temporaryURL, response) = try await URLSession.shared.download(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                throw AppUpdateError.invalidResponse
            }
            guard httpResponse.statusCode == 200 else {
                throw AppUpdateError.server(httpResponse.statusCode)
            }

            let values = try temporaryURL.resourceValues(forKeys: [.fileSizeKey])
            let actualSize = Int64(values.fileSize ?? 0)
            guard actualSize == release.asset.size else {
                throw AppUpdateError.sizeMismatch(expected: release.asset.size, actual: actualSize)
            }

            let expectedDigest = try sha256Digest(from: release.asset)
            let actualDigest = try sha256(of: temporaryURL)
            guard actualDigest.caseInsensitiveCompare(expectedDigest) == .orderedSame else {
                throw AppUpdateError.checksumMismatch
            }

            let destination = try uniqueDownloadDestination(filename: release.asset.name)
            try FileManager.default.moveItem(at: temporaryURL, to: destination)
            downloadedInstallerURL = destination
            await installDownloadedUpdate(installer: destination)
        } catch {
            let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            errorMessage = message
            statusMessage = "下载更新失败"
        }
    }

    func openReleasePage() {
        NSWorkspace.shared.open(availableRelease?.releaseURL ?? latestRelease?.releaseURL ?? releasesPage)
    }

    private func loadLatestRelease() async throws -> AppUpdateRelease {
        do {
            return try await loadManifestRelease()
        } catch {
            return try await loadGitHubAPIRelease()
        }
    }

    private func loadManifestRelease() async throws -> AppUpdateRelease {
        var request = URLRequest(url: latestManifest)
        request.timeoutInterval = 20
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("ClaudexDual/\(currentVersion)", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw AppUpdateError.invalidResponse
        }
        guard httpResponse.statusCode == 200 else {
            throw AppUpdateError.server(httpResponse.statusCode)
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let manifest = try decoder.decode(AppUpdateManifest.self, from: data)
        guard AppSemanticVersion(manifest.version) != nil,
              AppSemanticVersion(manifest.tagName) == AppSemanticVersion(manifest.version) else {
            throw AppUpdateError.invalidRelease
        }
        let asset = GitHubReleaseAsset(
            name: manifest.asset.name,
            browserDownloadURL: manifest.asset.url,
            size: manifest.asset.size,
            digest: "sha256:\(manifest.asset.sha256)"
        )
        try validate(asset: asset)
        return AppUpdateRelease(
            tagName: manifest.tagName,
            version: manifest.version,
            title: manifest.title,
            notes: manifest.notes.trimmingCharacters(in: .whitespacesAndNewlines),
            releaseURL: manifest.releaseURL,
            publishedAt: manifest.publishedAt,
            asset: asset
        )
    }

    private func loadGitHubAPIRelease() async throws -> AppUpdateRelease {
        var request = URLRequest(url: releasesAPI)
        request.timeoutInterval = 20
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("ClaudexDual/\(currentVersion)", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw AppUpdateError.invalidResponse
        }
        guard httpResponse.statusCode == 200 else {
            throw AppUpdateError.server(httpResponse.statusCode)
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let responseRelease = try decoder.decode(GitHubReleaseResponse.self, from: data)
        guard AppSemanticVersion(responseRelease.tagName) != nil else {
            throw AppUpdateError.invalidRelease
        }
        guard let asset = responseRelease.assets.first(where: { $0.name.lowercased().hasSuffix(".dmg") }) else {
            throw AppUpdateError.missingInstaller
        }
        try validate(asset: asset)
        return AppUpdateRelease(
            tagName: responseRelease.tagName,
            version: responseRelease.tagName.hasPrefix("v") ? String(responseRelease.tagName.dropFirst()) : responseRelease.tagName,
            title: responseRelease.name ?? "ClaudexDual \(responseRelease.tagName)",
            notes: responseRelease.body?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "本版本未提供更新说明。",
            releaseURL: responseRelease.htmlURL,
            publishedAt: responseRelease.publishedAt,
            asset: asset
        )
    }

    private func loadLatestTagFromReleasePage() async throws -> String {
        var request = URLRequest(url: latestReleasePage)
        request.timeoutInterval = 20
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("ClaudexDual/\(currentVersion)", forHTTPHeaderField: "User-Agent")
        let (_, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200,
              let finalURL = httpResponse.url,
              finalURL.host?.lowercased() == "github.com",
              finalURL.path.contains("/saibogoo/ClaudeDual/releases/tag/") else {
            throw AppUpdateError.invalidResponse
        }
        let tag = finalURL.lastPathComponent.removingPercentEncoding ?? finalURL.lastPathComponent
        guard AppSemanticVersion(tag) != nil else { throw AppUpdateError.invalidRelease }
        return tag
    }

    private func validate(asset: GitHubReleaseAsset) throws {
        guard asset.browserDownloadURL.scheme == "https",
              asset.browserDownloadURL.host?.lowercased() == "github.com",
              asset.browserDownloadURL.path.hasPrefix(trustedDownloadPathPrefix) else {
            throw AppUpdateError.untrustedDownloadURL
        }
        guard asset.name.lowercased().hasSuffix(".dmg"),
              asset.size > 0,
              asset.size <= 512 * 1024 * 1024 else {
            throw AppUpdateError.missingInstaller
        }
        _ = try sha256Digest(from: asset)
    }

    private func sha256Digest(from asset: GitHubReleaseAsset) throws -> String {
        guard let digest = asset.digest else { throw AppUpdateError.missingDigest }
        let parts = digest.split(separator: ":", maxSplits: 1).map(String.init)
        guard parts.count == 2,
              parts[0].lowercased() == "sha256",
              parts[1].count == 64,
              parts[1].allSatisfy({ $0.isHexDigit }) else {
            throw AppUpdateError.invalidDigest
        }
        return parts[1]
    }

    private func sha256(of fileURL: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: fileURL)
        defer { try? handle.close() }
        var hasher = SHA256()
        while true {
            let data = handle.readData(ofLength: 1024 * 1024)
            if data.isEmpty { break }
            hasher.update(data: data)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    /// 校验通过后自动完成安装：挂载 DMG、暂存新版本、由外部脚本在本进程退出后替换并重启。
    /// 任何一步失败都回退到打开 DMG 让用户手动拖拽。
    private func installDownloadedUpdate(installer: URL) async {
        isInstalling = true
        statusMessage = "正在安装更新…"
        let bundleURL = Bundle.main.bundleURL
        do {
            let plan = try await Task.detached(priority: .userInitiated) {
                try AppUpdateManager.prepareInstallation(installer: installer, currentBundle: bundleURL)
            }.value
            statusMessage = "安装完成，正在重启…"
            try AppUpdateManager.launchReplacer(plan)
            isInstalling = false
            // 交给脚本接管：它会等本进程退出后替换并重新打开应用。
            NSApplication.shared.terminate(nil)
        } catch {
            isInstalling = false
            let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            errorMessage = "\(message) 已打开安装包，请手动拖入“应用程序”完成升级。"
            statusMessage = "自动安装未完成，请手动安装"
            NSWorkspace.shared.open(installer)
        }
    }

    fileprivate struct InstallPlan {
        let stagedApp: URL
        let destination: URL
        let scriptURL: URL
        let installer: URL
    }

    /// 挂载安装包并把新版本拷贝到临时目录，同时生成替换脚本。全部在后台线程执行。
    fileprivate nonisolated static func prepareInstallation(installer: URL, currentBundle: URL) throws -> InstallPlan {
        let work = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("ClaudexDualUpdate-\(UUID().uuidString)")
        let mountPoint = work.appendingPathComponent("mount")
        let staging = work.appendingPathComponent("staging")
        try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)

        let mount = run("/usr/bin/hdiutil", ["attach", installer.path, "-nobrowse", "-readonly",
                                             "-mountpoint", mountPoint.path])
        guard mount.status == 0 else {
            throw AppUpdateError.mountFailed(mount.output.isEmpty ? "hdiutil 退出码 \(mount.status)" : mount.output)
        }
        defer { _ = run("/usr/bin/hdiutil", ["detach", mountPoint.path, "-quiet", "-force"]) }

        let entries = (try? FileManager.default.contentsOfDirectory(at: mountPoint,
                                                                    includingPropertiesForKeys: nil)) ?? []
        guard let sourceApp = entries.first(where: { $0.pathExtension == "app" }) else {
            throw AppUpdateError.installerAppMissing
        }

        // 安装到当前应用所在目录；改名后新旧同名才会被覆盖。
        let installDir = currentBundle.deletingLastPathComponent()
        guard FileManager.default.isWritableFile(atPath: installDir.path) else {
            throw AppUpdateError.destinationNotWritable(installDir.path)
        }

        let stagedApp = staging.appendingPathComponent(sourceApp.lastPathComponent)
        let copy = run("/usr/bin/ditto", [sourceApp.path, stagedApp.path])
        guard copy.status == 0 else {
            throw AppUpdateError.installFailed(copy.output.isEmpty ? "ditto 退出码 \(copy.status)" : copy.output)
        }
        // 下载来的包带隔离属性，不清除会被 Gatekeeper 拦下。
        _ = run("/usr/bin/xattr", ["-dr", "com.apple.quarantine", stagedApp.path])

        let destination = installDir.appendingPathComponent(sourceApp.lastPathComponent)
        let scriptURL = work.appendingPathComponent("install.sh")
        let script = """
        #!/bin/bash
        # 由 ClaudexDual 在线升级生成：等待应用退出后替换并重启。
        set -u
        DEST=\(shellQuoted(destination.path))
        STAGED=\(shellQuoted(stagedApp.path))
        BACKUP="$DEST.oldversion"
        WORK=\(shellQuoted(work.path))
        INSTALLER=\(shellQuoted(installer.path))

        for _ in $(seq 1 100); do
          kill -0 \(ProcessInfo.processInfo.processIdentifier) 2>/dev/null || break
          sleep 0.2
        done
        sleep 0.5

        rm -rf "$BACKUP"
        if [ -d "$DEST" ] && ! mv "$DEST" "$BACKUP"; then
          open "$INSTALLER"
          exit 1
        fi
        if ditto "$STAGED" "$DEST"; then
          rm -rf "$BACKUP"
          xattr -dr com.apple.quarantine "$DEST" 2>/dev/null
          open "$DEST"
        else
          # 复制失败则回滚到旧版本，并退回手动安装。
          rm -rf "$DEST"
          [ -d "$BACKUP" ] && mv "$BACKUP" "$DEST"
          [ -d "$DEST" ] && open "$DEST"
          open "$INSTALLER"
        fi
        rm -rf "$WORK"
        """
        try script.write(to: scriptURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptURL.path)
        return InstallPlan(stagedApp: stagedApp, destination: destination, scriptURL: scriptURL, installer: installer)
    }

    /// 以脱离父进程的方式启动替换脚本，使其在本应用退出后继续执行。
    fileprivate nonisolated static func launchReplacer(_ plan: InstallPlan) throws {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/bash")
        task.arguments = [plan.scriptURL.path]
        task.standardOutput = FileHandle.nullDevice
        task.standardError = FileHandle.nullDevice
        try task.run()
    }

    private nonisolated static func shellQuoted(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    @discardableResult
    private nonisolated static func run(_ path: String, _ arguments: [String]) -> (status: Int32, output: String) {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: path)
        task.arguments = arguments
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = pipe
        do {
            try task.run()
        } catch {
            return (-1, error.localizedDescription)
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        task.waitUntilExit()
        let text = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return (task.terminationStatus, text)
    }

    private func uniqueDownloadDestination(filename: String) throws -> URL {
        let downloads = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Downloads", isDirectory: true)
        try FileManager.default.createDirectory(at: downloads, withIntermediateDirectories: true)

        let sourceName = (filename as NSString).deletingPathExtension
        let pathExtension = (filename as NSString).pathExtension
        var destination = downloads.appendingPathComponent(filename)
        var suffix = 2
        while FileManager.default.fileExists(atPath: destination.path) {
            destination = downloads.appendingPathComponent("\(sourceName)-\(suffix).\(pathExtension)")
            suffix += 1
        }
        return destination
    }
}

// MARK: - App Entry Point

@main
struct ClaudexDualApp: App {
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

class ClaudexDualManager: ObservableObject {
    @Published var selectedClient: ManagedClient = .claude
    @Published var isClaudeInstalled = false
    @Published var isInstanceRunning = false
    @Published var isInstanceStarting = false
    @Published var isInstanceStopping = false
    @Published var isConfigured = false
    @Published var isDeveloperModeEnabled = false
    @Published var instancePID: String = ""
    @Published var isCodexInstalled = false
    @Published var isCodexInstanceRunning = false
    @Published var isCodexInstanceStarting = false
    @Published var isCodexInstanceStopping = false
    @Published var isCodexConfigured = false
    @Published var codexInstancePID: String = ""
    @Published var logs: [LogEntry] = []

    // Multi-config support
    @Published var profiles: [ConfigProfile] = []
    @Published var activeProfileId: UUID?

    // Proxy support
    @Published var isProxyRunning = false
    @Published var proxyPort: Int
    @Published var isCodexProxyRunning = false
    @Published var codexProxyPort: Int

    var activeProfile: ConfigProfile? {
        profiles.first { $0.id == activeProfileId }
    }

    private func activeProfile(for _: ManagedClient) -> ConfigProfile? {
        activeProfile
    }

    var sharedProfiles: [ConfigProfile] {
        profiles
    }

    var sharedActiveProfileId: UUID? {
        activeProfileId
    }

    var selectedIsInstalled: Bool {
        selectedClient == .claude ? isClaudeInstalled : isCodexInstalled
    }

    var selectedIsInstanceRunning: Bool {
        selectedClient == .claude ? isInstanceRunning : isCodexInstanceRunning
    }

    var selectedIsInstanceStarting: Bool {
        selectedClient == .claude ? isInstanceStarting : isCodexInstanceStarting
    }

    var selectedIsInstanceStopping: Bool {
        selectedClient == .claude ? isInstanceStopping : isCodexInstanceStopping
    }

    var selectedIsConfigured: Bool {
        selectedClient == .claude ? isConfigured : isCodexConfigured
    }

    var selectedIsEnvironmentReady: Bool {
        selectedClient == .claude ? isDeveloperModeEnabled : isCodexConfigured
    }

    var selectedInstancePID: String {
        selectedClient == .claude ? instancePID : codexInstancePID
    }

    var selectedIsProxyRunning: Bool {
        selectedClient == .claude ? isProxyRunning : isCodexProxyRunning
    }

    var selectedProxyPort: Int {
        selectedClient == .claude ? proxyPort : codexProxyPort
    }

    var selectedLogs: [LogEntry] {
        logs.filter { $0.client == selectedClient }
    }

    let dataDir: String
    let configDir: String
    let legacyDataDir: String
    let claudeApp = "/Applications/Claude.app"
    let claudeDownloadURL = URL(string: "https://claude.com/download")!
    let codexDownloadURL = URL(string: "https://chatgpt.com/download")!
    let codexDataDir: String
    let codexHomeDir: String
    let codexUserDataDir: String
    let configId = "7595758f-4aab-4d2e-9bf8-b0abfc5616e4"
    let localProxyApiKey = "claude-dual-local-proxy"

    private var proxyProcess: Process?
    private var proxyScriptPath: String?
    private var proxyConfigPath: String?
    private var codexProxyProcess: Process?
    private var codexProxyScriptPath: String?
    private var codexProxyConfigPath: String?
    // A key is fetched from Keychain at most once per profile while this app is
    // running.  In particular, do not ask once in Swift and then again from
    // every proxy/Codex child process.
    private var profileApiKeyCache: [UUID: String] = [:]
    private var attemptedKeychainLookups = Set<UUID>()
    private let proxyAPIKeyEnvironment = "CLAUDE_DUAL_PROXY_API_KEY"
    private let codexAPIKeyEnvironment = "CLAUDE_DUAL_CODEX_API_KEY"

    private let defaults = UserDefaults.standard
    private let profilesKey = "ck.profiles"
    private let activeProfileKey = "ck.activeProfileId"
    private let legacyCodexActiveProfileKey = "ck.codexActiveProfileId"
    private let proxyPortKey = "ck.proxyPort"
    private let codexProxyPortKey = "ck.codexProxyPort"
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
        codexDataDir = "\(home)/Library/Application Support/ClaudeDual/CodexInstances/default"
        codexHomeDir = "\(home)/Library/Application Support/ClaudeDual/CodexInstances/default/codex-home"
        codexUserDataDir = "\(home)/Library/Application Support/ClaudeDual/CodexInstances/default/electron-data"

        let storedProxyPort = defaults.integer(forKey: proxyPortKey)
        let storedCodexProxyPort = defaults.integer(forKey: codexProxyPortKey)
        proxyPort = storedProxyPort == 0 ? 3456 : storedProxyPort
        codexProxyPort = storedCodexProxyPort == 0 ? 3460 : storedCodexProxyPort

        loadProfiles()
        migrateLegacyDataIfNeeded()
        NSLog("[CD] Manager init: profiles loaded, count=\(profiles.count)")

        // Defer heavy I/O to background to avoid blocking UI init
        DispatchQueue.global(qos: .userInitiated).async {
            let installed = self.claudeAppPath() != nil
            let codexInstalled = self.codexAppPath() != nil
            let configFile = "\(self.configDir)/\(self.configId).json"
            let configured = FileManager.default.fileExists(atPath: configFile)
            let codexConfigured = FileManager.default.fileExists(atPath: "\(self.codexHomeDir)/config.toml")
            let developerModeEnabled = self.detectDeveloperModeEnabled()
            DispatchQueue.main.async {
                self.isClaudeInstalled = installed
                self.isCodexInstalled = codexInstalled
                self.isConfigured = configured
                self.isCodexConfigured = codexConfigured
                self.isDeveloperModeEnabled = developerModeEnabled
                NSLog("[CD] Manager init: async status updated, installed=\(installed), configured=\(configured), developerMode=\(developerModeEnabled)")
            }
            self.checkRunningInstance()
            self.checkProxyRunning()
            self.checkCodexRunningInstance()
            self.checkCodexProxyRunning()
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
            if let legacyCodexId = defaults.string(forKey: legacyCodexActiveProfileKey).flatMap(UUID.init(uuidString:)),
               profiles.contains(where: { $0.id == legacyCodexId }) {
                activeProfileId = legacyCodexId
            } else {
                activeProfileId = profiles.first?.id
            }
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
            // Profile recovery runs during app startup.  Keychain access here
            // used to generate several authorization prompts before a user
            // even requested a launch.
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
            if let url = profile.claudeApiBaseUrl {
                normalized.claudeApiBaseUrl = url.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            if let url = profile.codexApiBaseUrl {
                normalized.codexApiBaseUrl = url.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            // Do not migrate legacy values into Keychain while loading the
            // app.  The migration is performed when the user saves that
            // profile, avoiding unsolicited Keychain prompts at startup.
            normalized.apiKey = profile.effectiveApiKey
            normalized.modelName = profile.effectiveUpstreamModel
            normalized.allowedHosts = profile.allowedHosts.trimmingCharacters(in: .whitespacesAndNewlines)
            normalized.client = nil
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

    func addProfile(name: String, apiBaseUrl: String, apiKey: String, authScheme: String, modelName: String, allowedHosts: String, proxyMode: String? = nil, ccSwitchUrl: String? = nil, claudeApiBaseUrl: String? = nil, codexApiBaseUrl: String? = nil) -> ConfigProfile {
        var profile = ConfigProfile(
            id: UUID(),
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            apiBaseUrl: apiBaseUrl.trimmingCharacters(in: .whitespacesAndNewlines),
            apiKey: apiKey.trimmingCharacters(in: .whitespacesAndNewlines),
            authScheme: authScheme,
            modelName: modelName.trimmingCharacters(in: .whitespacesAndNewlines),
            allowedHosts: allowedHosts.trimmingCharacters(in: .whitespacesAndNewlines),
            proxyMode: proxyMode ?? "localProxy",
            ccSwitchUrl: ccSwitchUrl,
            claudeApiBaseUrl: claudeApiBaseUrl,
            codexApiBaseUrl: codexApiBaseUrl,
            client: nil
        )
        if !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            _ = storeProfileApiKey(apiKey, profileId: profile.id)
            profile.apiKey = ""
        }
        profiles.append(profile)
        saveProfilesToDefaults()
        addLog("➕ 已添加配置: \(name)", type: .info)
        return profile
    }

    func updateProfile(id: UUID, name: String, apiBaseUrl: String, apiKey: String, authScheme: String, modelName: String, allowedHosts: String, proxyMode: String?, ccSwitchUrl: String?, claudeApiBaseUrl: String? = nil, codexApiBaseUrl: String? = nil) {
        guard let index = profiles.firstIndex(where: { $0.id == id }) else { return }
        profiles[index].name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        profiles[index].apiBaseUrl = apiBaseUrl.trimmingCharacters(in: .whitespacesAndNewlines)
        profiles[index].apiKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        profiles[index].authScheme = authScheme
        profiles[index].modelName = modelName.trimmingCharacters(in: .whitespacesAndNewlines)
        profiles[index].allowedHosts = allowedHosts.trimmingCharacters(in: .whitespacesAndNewlines)
        profiles[index].proxyMode = proxyMode
        profiles[index].ccSwitchUrl = ccSwitchUrl
        profiles[index].claudeApiBaseUrl = claudeApiBaseUrl
        profiles[index].codexApiBaseUrl = codexApiBaseUrl
        if !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            _ = storeProfileApiKey(apiKey, profileId: id)
            profiles[index].apiKey = ""
        }
        saveProfilesToDefaults()

        if sharedActiveProfileId == id {
            if isProxyRunning { _ = startProxy(for: .claude) }
            if isCodexProxyRunning { _ = startProxy(for: .codex) }
            _ = saveConfigToDisk(for: .claude)
            _ = saveConfigToDisk(for: .codex)
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
        profileApiKeyCache.removeValue(forKey: id)
        attemptedKeychainLookups.remove(id)
        deleteProfileApiKey(profileId: id)

        if sharedActiveProfileId == id {
            activeProfileId = profiles.first?.id
            saveConfigToDisk(for: .claude)
            _ = saveConfigToDisk(for: .codex)
        }

        saveProfilesToDefaults()
        addLog("🗑 已删除配置: \(name)", type: .info)
    }

    func activateProfile(id: UUID) {
        guard profiles.contains(where: { $0.id == id }) else { return }
        activeProfileId = id
        saveProfilesToDefaults()
        if isProxyRunning { _ = startProxy(for: .claude) }
        if isCodexProxyRunning { _ = startProxy(for: .codex) }
        _ = saveConfigToDisk(for: .claude)
        _ = saveConfigToDisk(for: .codex)
        if let name = activeProfile?.name {
            addLog("🔀 已切换到配置: \(name)", type: .info)
        }
    }

    func duplicateProfile(id: UUID) {
        guard let profile = profiles.first(where: { $0.id == id }) else { return }
        var copy = profile
        copy.id = UUID()
        copy.name = profile.name + " 副本"
        _ = storeProfileApiKey(apiKey(for: profile), profileId: copy.id)
        copy.apiKey = ""
        profiles.append(copy)
        saveProfilesToDefaults()
        addLog("📋 已复制配置: \(profile.name)", type: .info)
    }

    private func profileKeychainService(profileId: UUID) -> String {
        // Keep the original service prefix so keys created by earlier builds remain available.
        "ClaudeDual.Codex.\(profileId.uuidString)"
    }

    func apiKey(for profile: ConfigProfile) -> String {
        if let cached = profileApiKeyCache[profile.id] {
            return cached
        }
        if attemptedKeychainLookups.contains(profile.id) {
            return profile.effectiveApiKey
        }
        attemptedKeychainLookups.insert(profile.id)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: profileKeychainService(profileId: profile.id),
            kSecAttrAccount as String: "api-key",
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: CFTypeRef?
        if SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
           let data = result as? Data,
           let value = String(data: data, encoding: .utf8) {
            profileApiKeyCache[profile.id] = value
            return value
        }
        let fallback = profile.effectiveApiKey
        profileApiKeyCache[profile.id] = fallback
        return fallback
    }

    @discardableResult
    private func storeProfileApiKey(_ value: String, profileId: UUID) -> Bool {
        let key = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return true }
        let lookup: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: profileKeychainService(profileId: profileId),
            kSecAttrAccount as String: "api-key"
        ]
        let attributes: [String: Any] = [kSecValueData as String: Data(key.utf8)]
        let status = SecItemUpdate(lookup as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            var item = lookup
            item[kSecValueData as String] = Data(key.utf8)
            let stored = SecItemAdd(item as CFDictionary, nil) == errSecSuccess
            if stored {
                profileApiKeyCache[profileId] = key
                attemptedKeychainLookups.insert(profileId)
            }
            return stored
        }
        let stored = status == errSecSuccess
        if stored {
            profileApiKeyCache[profileId] = key
            attemptedKeychainLookups.insert(profileId)
        }
        return stored
    }

    private func deleteProfileApiKey(profileId: UUID) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: profileKeychainService(profileId: profileId),
            kSecAttrAccount as String: "api-key"
        ]
        SecItemDelete(query as CFDictionary)
    }

    // MARK: - Proxy Management

    func startProxy(for client: ManagedClient? = nil) -> Bool {
        let targetClient = client ?? selectedClient
        if targetClient == .codex {
            return startCodexProxy()
        }
        guard let profile = activeProfile else {
            addLog("⚠️ 没有激活的配置", type: .warning)
            return false
        }

        // Stop existing proxy first
        if isProxyRunning {
            stopClaudeProxy()
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

        var proxyConfig: [String: Any] = [
            "port": proxyPort,
            "target_url": profile.effectiveClaudeApiBaseUrl,
            "auth_scheme": profile.effectiveAuthScheme,
            "model_name": profile.effectiveUpstreamModel
        ]
        let proxyApiKey = apiKey(for: profile)
        if !proxyApiKey.isEmpty {
            proxyConfig["api_key_env"] = proxyAPIKeyEnvironment
        }

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
        task.environment = ProcessInfo.processInfo.environment.merging(
            proxyApiKey.isEmpty ? [:] : [proxyAPIKeyEnvironment: proxyApiKey],
            uniquingKeysWith: { _, new in new }
        )
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
        if selectedClient == .codex {
            stopCodexProxy()
            return
        }
        stopClaudeProxy()
    }

    private func stopClaudeProxy(logEvent: Bool = true) {
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
        if logEvent {
            addLog("⏹ 代理服务器已停止", type: .info, client: .claude)
        }
    }

    private func startCodexProxy() -> Bool {
        guard let profile = activeProfile else {
            addLog("⚠️ 没有激活的 Codex 配置", type: .warning, client: .codex)
            return false
        }

        stopCodexProxy(logEvent: false)
        cleanupCodexProxyProcesses()

        guard isPython3Available() else {
            addLog("❌ 未检测到 Python3，无法启动 Codex 本地代理", type: .error, client: .codex)
            return false
        }

        if !isPortAvailable(codexProxyPort) {
            guard let newPort = findAvailablePort(startingFrom: codexProxyPort + 1) else {
                addLog("❌ 无法为 Codex 找到可用代理端口", type: .error, client: .codex)
                return false
            }
            codexProxyPort = newPort
            defaults.set(newPort, forKey: codexProxyPortKey)
            addLog("✅ Codex 已切换到可用端口: \(newPort)", type: .success, client: .codex)
        }

        let tempDir = FileManager.default.temporaryDirectory.path
        let suffix = profile.id.uuidString
        codexProxyConfigPath = "\(tempDir)/claude-dual-codex-proxy-config-\(suffix).json"
        codexProxyScriptPath = "\(tempDir)/claude-dual-codex-proxy-script-\(suffix).py"
        var proxyConfig: [String: Any] = [
            "port": codexProxyPort,
            "target_url": profile.effectiveCodexApiBaseUrl,
            "auth_scheme": profile.effectiveAuthScheme,
            "model_name": profile.effectiveUpstreamModel
        ]
        let proxyApiKey = apiKey(for: profile)
        if !proxyApiKey.isEmpty {
            proxyConfig["api_key_env"] = proxyAPIKeyEnvironment
        }

        guard let scriptContent = loadProxyScript(),
              let configPath = codexProxyConfigPath,
              let scriptPath = codexProxyScriptPath else {
            addLog("❌ 无法准备 Codex 代理文件", type: .error, client: .codex)
            return false
        }

        do {
            let configData = try JSONSerialization.data(withJSONObject: proxyConfig, options: .prettyPrinted)
            try configData.write(to: URL(fileURLWithPath: configPath), options: .atomic)
            try scriptContent.write(toFile: scriptPath, atomically: true, encoding: .utf8)
        } catch {
            addLog("❌ 写入 Codex 代理文件失败: \(error.localizedDescription)", type: .error, client: .codex)
            return false
        }

        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
        task.arguments = [scriptPath, configPath]
        task.environment = ProcessInfo.processInfo.environment.merging(
            proxyApiKey.isEmpty ? [:] : [proxyAPIKeyEnvironment: proxyApiKey],
            uniquingKeysWith: { _, new in new }
        )
        task.standardOutput = Pipe()
        task.standardError = Pipe()
        do {
            try task.run()
            codexProxyProcess = task
            isCodexProxyRunning = true
            addLog("🔄 Codex 代理服务器启动中 (端口: \(codexProxyPort))...", type: .info, client: .codex)
            return true
        } catch {
            addLog("❌ Codex 代理启动失败: \(error.localizedDescription)", type: .error, client: .codex)
            return false
        }
    }

    private func stopCodexProxy(logEvent: Bool = true) {
        if let process = codexProxyProcess, process.isRunning {
            process.terminate()
        }
        codexProxyProcess = nil
        isCodexProxyRunning = false
        if logEvent {
            addLog("⏹ Codex 代理服务器已停止", type: .info, client: .codex)
        }
    }

    private func cleanupCodexProxyProcesses() {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/pkill")
        task.arguments = ["-f", "claude-dual-codex-proxy-script-"]
        task.standardOutput = Pipe()
        task.standardError = Pipe()
        try? task.run()
        task.waitUntilExit()
        usleep(200_000)
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
    func saveConfigToDisk(for client: ManagedClient? = nil) -> Bool {
        let targetClient = client ?? selectedClient
        if targetClient == .codex {
            return saveCodexConfigToDisk()
        }
        guard let profile = activeProfile(for: .claude) else {
            addLog("⚠️ 没有激活的 Claude 配置", type: .warning, client: .claude)
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
        } else if profile.isDirectMode {
            gatewayUrl = profile.effectiveClaudeApiBaseUrl
            gatewayApiKey = apiKey(for: profile)
            gatewayAuthScheme = profile.effectiveAuthScheme
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

    private func tomlString(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
    }

    @discardableResult
    private func saveCodexConfigToDisk() -> Bool {
        guard let profile = activeProfile(for: .codex) else {
            addLog("⚠️ 没有激活的 Codex 配置", type: .warning, client: .codex)
            return false
        }

        do {
            try FileManager.default.createDirectory(atPath: codexHomeDir, withIntermediateDirectories: true, attributes: nil)
            try FileManager.default.createDirectory(atPath: codexUserDataDir, withIntermediateDirectories: true, attributes: nil)
        } catch {
            addLog("❌ 创建 Codex 隔离目录失败: \(error.localizedDescription)", type: .error, client: .codex)
            return false
        }

        let providerId = "claudedual_\(profile.id.uuidString.replacingOccurrences(of: "-", with: "").lowercased())"
        let baseURL: String
        if profile.isCcSwitchMode {
            baseURL = profile.effectiveCcSwitchUrl
        } else if profile.isDirectMode {
            baseURL = profile.effectiveCodexApiBaseUrl
        } else {
            baseURL = "http://127.0.0.1:\(codexProxyPort)/v1"
        }
        var lines = [
            "# Generated by ClaudexDual. This file belongs only to the isolated Codex instance.",
            "model = \"\(tomlString(profile.effectiveUpstreamModel))\"",
            "model_provider = \"\(providerId)\"",
            "cli_auth_credentials_store = \"file\"",
            "",
            "[model_providers.\(providerId)]",
            "name = \"ClaudexDual \(tomlString(profile.name))\"",
            "base_url = \"\(tomlString(baseURL))\"",
            "wire_api = \"responses\""
        ]

        // Codex receives a direct-mode key from the launch environment.  Do
        // not generate a `security find-generic-password` command: it would
        // make the isolated Codex process request Keychain access repeatedly.
        if profile.isDirectMode {
            lines.append(contentsOf: [
                "",
                "env_key = \"\(codexAPIKeyEnvironment)\""
            ])
        }

        let content = lines.joined(separator: "\n") + "\n"
        let path = "\(codexHomeDir)/config.toml"
        do {
            try content.write(toFile: path, atomically: true, encoding: .utf8)
            isCodexConfigured = true
            addLog("✅ Codex 隔离配置已保存", type: .success, client: .codex)
            return true
        } catch {
            addLog("❌ 写入 Codex 配置失败: \(error.localizedDescription)", type: .error, client: .codex)
            return false
        }
    }

    func enableDeveloperMode() {
        if selectedClient == .codex {
            guard !isCodexInstanceStarting && !isCodexInstanceStopping else {
                addLog("⚠️ Codex 操作进行中，请稍候", type: .warning, client: .codex)
                return
            }
            if saveCodexConfigToDisk() {
                addLog("✅ Codex 隔离环境已初始化", type: .success, client: .codex)
            }
            return
        }
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
        stopClaudeProxy()
        stopCodexProxy()
        profiles.forEach { deleteProfileApiKey(profileId: $0.id) }
        try? FileManager.default.removeItem(atPath: configDir)
        try? FileManager.default.removeItem(atPath: codexDataDir)
        let profile = ConfigProfile.makeDefault()
        profiles = [profile]
        activeProfileId = profile.id
        proxyPort = 3456
        codexProxyPort = 3460
        defaults.set(proxyPort, forKey: proxyPortKey)
        defaults.set(codexProxyPort, forKey: codexProxyPortKey)
        saveProfilesToDefaults()
        _ = saveConfigToDisk(for: .claude)
        _ = saveConfigToDisk(for: .codex)
        addLog("🔄 已恢复默认配置", type: .info)
    }

    // MARK: - Status & Process Management

    func refreshStatus() {
        isClaudeInstalled = claudeAppPath() != nil
        isCodexInstalled = codexAppPath() != nil
        let configFile = "\(configDir)/\(configId).json"
        isConfigured = FileManager.default.fileExists(atPath: configFile)
        isCodexConfigured = FileManager.default.fileExists(atPath: "\(codexHomeDir)/config.toml")
        isDeveloperModeEnabled = detectDeveloperModeEnabled()
        DispatchQueue.global(qos: .background).async {
            self.checkRunningInstance()
            self.checkProxyRunning()
            self.checkCodexRunningInstance()
            self.checkCodexProxyRunning()
        }
    }

    func openSelectedDownloadPage() {
        NSWorkspace.shared.open(selectedClient == .claude ? claudeDownloadURL : codexDownloadURL)
    }

    private func usableApplicationPath(_ appPath: String) -> String? {
        let infoPath = "\(appPath)/Contents/Info.plist"
        guard let info = NSDictionary(contentsOfFile: infoPath),
              let executable = info["CFBundleExecutable"] as? String else {
            return nil
        }
        let executablePath = "\(appPath)/Contents/MacOS/\(executable)"
        return FileManager.default.isExecutableFile(atPath: executablePath) ? appPath : nil
    }

    private func claudeAppPath() -> String? {
        usableApplicationPath(claudeApp)
    }

    private func codexAppPath() -> String? {
        let candidates = ["/Applications/ChatGPT.app", "/Applications/Codex.app"]
        return candidates.first(where: { usableApplicationPath($0) != nil })
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

    private func runningCodexInstancePID() -> String {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/bash")
        task.arguments = ["-c", "ps aux | grep -- '--user-data-dir=\(codexUserDataDir)' | grep -v grep | awk '{print $2}' | head -1"]
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

    func checkCodexRunningInstance() {
        let pid = runningCodexInstancePID()
        DispatchQueue.main.async {
            self.codexInstancePID = pid
            self.isCodexInstanceRunning = !pid.isEmpty
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

    func checkCodexProxyRunning() {
        let running = codexProxyProcess?.isRunning == true
        DispatchQueue.main.async {
            self.isCodexProxyRunning = running
        }
    }

    func startInstance() {
        if selectedClient == .codex {
            startCodexInstance()
            return
        }
        guard let _ = claudeAppPath() else {
            isClaudeInstalled = false
            addLog("❌ Claude Desktop 未安装或应用已损坏（缺少可执行文件）", type: .error)
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

        if profile.isCcSwitchMode || profile.isDirectMode {
            let modeName = profile.isCcSwitchMode ? "CC-Switch" : "直连"
            addLog("⏳ 正在启动 (\(modeName) 模式)...", type: .info)
            isProxyRunning = false
            saveConfigToDisk(for: .claude)
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
                self.saveConfigToDisk(for: .claude)
                self.launchClaudeInstance()
            }
        }
    }

    private func launchClaudeInstance() {
        guard let appPath = claudeAppPath() else {
            isClaudeInstalled = false
            isInstanceStarting = false
            addLog("❌ Claude Desktop 未安装或应用已损坏（缺少可执行文件）", type: .error)
            return
        }
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        task.arguments = ["-n", "-a", appPath, "--args", "--user-data-dir=\(dataDir)"]
        let errorPipe = Pipe()
        task.standardOutput = Pipe()
        task.standardError = errorPipe
        task.terminationHandler = { [weak self] process in
            let detail = String(
                data: errorPipe.fileHandleForReading.readDataToEndOfFile(),
                encoding: .utf8
            )?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard process.terminationStatus != 0 else { return }
            DispatchQueue.main.async {
                self?.isInstanceStarting = false
                self?.addLog("❌ Claude 启动失败\(detail.isEmpty ? "" : ": \(detail)")", type: .error)
            }
        }
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

    private func startCodexInstance() {
        guard let _ = codexAppPath() else {
            isCodexInstalled = false
            addLog("❌ Codex Desktop 未安装或应用已损坏（缺少可执行文件）", type: .error, client: .codex)
            return
        }
        guard !isCodexInstanceStarting && !isCodexInstanceStopping else {
            addLog("⚠️ Codex 操作进行中，请稍候", type: .warning, client: .codex)
            return
        }
        guard !isCodexInstanceRunning else {
            addLog("⚠️ Codex 隔离实例已在运行 (PID: \(codexInstancePID))", type: .warning, client: .codex)
            return
        }
        guard isCodexConfigured else {
            addLog("⚠️ 请先初始化 Codex 隔离环境", type: .warning, client: .codex)
            return
        }
        guard let profile = activeProfile else {
            addLog("⚠️ 没有激活的 Codex 配置", type: .warning, client: .codex)
            return
        }

        isCodexInstanceStarting = true
        if profile.isDirectMode || profile.isCcSwitchMode {
            isCodexProxyRunning = false
            guard saveCodexConfigToDisk() else {
                isCodexInstanceStarting = false
                return
            }
            launchCodexInstance()
            return
        }

        addLog("⏳ 正在准备 Codex 隔离实例...", type: .info, client: .codex)
        let proxyStarted = startCodexProxy()
        DispatchQueue.main.asyncAfter(deadline: .now() + (proxyStarted ? 1.2 : 0)) {
            guard proxyStarted && self.isProxyPortReachable(self.codexProxyPort) else {
                self.isCodexProxyRunning = false
                self.isCodexInstanceStarting = false
                self.addLog("❌ Codex 代理端口未监听，已取消启动", type: .error, client: .codex)
                return
            }
            guard self.saveCodexConfigToDisk() else {
                self.isCodexInstanceStarting = false
                return
            }
            self.launchCodexInstance()
        }
    }

    private func launchCodexInstance() {
        guard let appPath = codexAppPath() else {
            isCodexInstalled = false
            isCodexInstanceStarting = false
            addLog("❌ Codex Desktop 未安装或应用已损坏（缺少可执行文件）", type: .error, client: .codex)
            return
        }
        guard let profile = activeProfile else {
            isCodexInstanceStarting = false
            addLog("⚠️ 没有激活的 Codex 配置", type: .warning, client: .codex)
            return
        }
        let directApiKey = profile.isDirectMode ? apiKey(for: profile) : ""
        if profile.isDirectMode && directApiKey.isEmpty {
            isCodexInstanceStarting = false
            addLog("❌ 直连模式缺少 API Key，无法启动 Codex", type: .error, client: .codex)
            return
        }
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        var arguments = [
            "-n",
            "--env", "CODEX_HOME=\(codexHomeDir)",
        ]
        if profile.isDirectMode {
            arguments += ["--env", "\(codexAPIKeyEnvironment)=\(directApiKey)"]
        }
        arguments += ["-a", appPath, "--args", "--user-data-dir=\(codexUserDataDir)"]
        task.arguments = arguments
        let errorPipe = Pipe()
        task.standardOutput = Pipe()
        task.standardError = errorPipe
        task.terminationHandler = { [weak self] process in
            let detail = String(
                data: errorPipe.fileHandleForReading.readDataToEndOfFile(),
                encoding: .utf8
            )?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard process.terminationStatus != 0 else { return }
            DispatchQueue.main.async {
                self?.isCodexInstanceStarting = false
                self?.addLog("❌ Codex 启动失败\(detail.isEmpty ? "" : ": \(detail)")", type: .error, client: .codex)
            }
        }
        do {
            try task.run()
            addLog("🚀 正在启动 Codex 隔离实例...", type: .info, client: .codex)
        } catch {
            isCodexInstanceStarting = false
            addLog("❌ Codex 启动失败: \(error.localizedDescription)", type: .error, client: .codex)
            return
        }

        DispatchQueue.global(qos: .background).asyncAfter(deadline: .now() + 3) {
            let pid = self.runningCodexInstancePID()
            DispatchQueue.main.async {
                self.codexInstancePID = pid
                self.isCodexInstanceRunning = !pid.isEmpty
                self.isCodexInstanceStarting = false
                if pid.isEmpty {
                    self.addLog("⏳ Codex 实例仍在启动，请稍候...", type: .info, client: .codex)
                } else {
                    self.addLog("🚀 Codex 隔离实例已启动 (PID: \(pid))", type: .success, client: .codex)
                }
            }
        }
    }

    private func stopCodexInstance() async {
        guard !isCodexInstanceStarting && !isCodexInstanceStopping else {
            addLog("⚠️ Codex 操作进行中，请稍候", type: .warning, client: .codex)
            return
        }
        guard isCodexInstanceRunning, !codexInstancePID.isEmpty else {
            addLog("⚠️ 没有运行中的 Codex 隔离实例", type: .warning, client: .codex)
            return
        }

        let savedPID = codexInstancePID
        await MainActor.run {
            isCodexInstanceStopping = true
            addLog("⏹ 正在停止 Codex 隔离实例 (PID: \(savedPID))...", type: .info, client: .codex)
        }
        await runCommand("/bin/kill", arguments: [savedPID])
        try? await Task.sleep(nanoseconds: 2_000_000_000)
        await runCommand("/usr/bin/pkill", arguments: ["-f", "user-data-dir=\(codexUserDataDir)"])
        try? await Task.sleep(nanoseconds: 1_000_000_000)
        var finalPID = runningCodexInstancePID()
        if !finalPID.isEmpty {
            await runCommand("/usr/bin/pkill", arguments: ["-9", "-f", "user-data-dir=\(codexUserDataDir)"])
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            finalPID = runningCodexInstancePID()
        }

        let resultPID = finalPID
        await MainActor.run {
            codexInstancePID = resultPID
            isCodexInstanceRunning = !resultPID.isEmpty
            isCodexInstanceStopping = false
            stopCodexProxy()
            addLog(
                resultPID.isEmpty ? "✅ Codex 隔离实例已完全停止" : "❌ Codex 仍有进程未能终止 (PID: \(resultPID))",
                type: resultPID.isEmpty ? .success : .error,
                client: .codex
            )
        }
    }

    func stopInstance() async {
        if selectedClient == .codex {
            await stopCodexInstance()
            return
        }
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
            stopClaudeProxy()
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
        let path = selectedClient == .claude ? dataDir : codexDataDir
        try? FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: true, attributes: nil)
        NSWorkspace.shared.open(URL(fileURLWithPath: path))
        addLog("📁 已打开数据目录", type: .info)
    }

    func addLog(_ message: String, type: LogType? = nil, client: ManagedClient? = nil) {
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

        let logClient = client ?? selectedClient
        DispatchQueue.main.async {
            self.logs.insert(LogEntry(time: time, message: message, type: logType, client: logClient), at: 0)
            if self.logs.count > 100 { self.logs.removeLast() }
        }
    }

    func clearLogs() {
        logs.removeAll { $0.client == selectedClient }
    }

    func setProxyPort(_ port: Int, for client: ManagedClient) {
        if client == .claude {
            proxyPort = port
            defaults.set(port, forKey: proxyPortKey)
        } else {
            codexProxyPort = port
            defaults.set(port, forKey: codexProxyPortKey)
        }
    }
}

// MARK: - Content View

struct ContentView: View {
    @StateObject private var manager = ClaudexDualManager()
    @StateObject private var updateManager = AppUpdateManager()
    @State private var selectedTab: AppTab = .status
    @State private var timer: Timer?
    @State private var showClientInstallPrompt = false
    @State private var showUpdatePrompt = false
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
                    AboutTab(updateManager: updateManager)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(AppTheme.canvas)
        }
        .tint(AppTheme.focus)
        .preferredColorScheme(AppAppearance(rawValue: appearancePreference)?.colorScheme)
        .frame(minWidth: 1040, minHeight: 680)
        .alert("未检测到 \(manager.selectedClient.desktopTitle)", isPresented: $showClientInstallPrompt) {
            Button("前往下载") {
                manager.openSelectedDownloadPage()
            }
            Button("重新检测") {
                manager.refreshStatus()
                if !manager.selectedIsInstalled {
                    DispatchQueue.main.async {
                        showClientInstallPrompt = true
                    }
                }
            }
            Button("稍后", role: .cancel) {}
        } message: {
            Text("ClaudexDual 需要 \(manager.selectedClient.desktopTitle) 才能启动隔离实例。请先安装客户端，然后返回并重新检测。")
        }
        .sheet(isPresented: $showUpdatePrompt) {
            UpdateAvailableSheet(updateManager: updateManager, isPresented: $showUpdatePrompt)
        }
        .onAppear {
            NSLog("[CD] ContentView.onAppear")
            manager.refreshStatus()
            showClientInstallPrompt = !manager.selectedIsInstalled
            Task {
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                let hasUpdate = await updateManager.checkForUpdates()
                if hasUpdate && !showClientInstallPrompt {
                    showUpdatePrompt = true
                }
            }
            timer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { _ in
                DispatchQueue.global(qos: .background).async {
                    self.manager.checkRunningInstance()
                    self.manager.checkProxyRunning()
                    self.manager.checkCodexRunningInstance()
                    self.manager.checkCodexProxyRunning()
                }
            }
        }
        .onChange(of: manager.selectedClient) { _ in
            manager.refreshStatus()
            showClientInstallPrompt = !manager.selectedIsInstalled
        }
        .onDisappear {
            timer?.invalidate()
        }
    }
}

struct AppSidebar: View {
    @Binding var selectedTab: AppTab
    @Binding var appearancePreference: String
    @ObservedObject var manager: ClaudexDualManager

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 11) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 38, height: 38)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

                VStack(alignment: .leading, spacing: 2) {
                    Text("ClaudexDual")
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                    Text("Desktop Console")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.secondary)
                }
            }
            .padding(.horizontal, 18)
            .padding(.top, 20)
            .padding(.bottom, 12)

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
                    .fill(manager.selectedIsInstanceRunning ? AppTheme.success : Color.secondary.opacity(0.45))
                    .frame(width: 8, height: 8)

                VStack(alignment: .leading, spacing: 2) {
                    Text(manager.selectedIsInstanceRunning ? "\(manager.selectedClient.title) 实例运行中" : "\(manager.selectedClient.title) 实例未运行")
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
    @ObservedObject var manager: ClaudexDualManager

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                PageHeader(
                    eyebrow: "工作台",
                    title: "运行概览",
                    subtitle: "查看 \(manager.selectedClient.desktopTitle)、隔离实例与代理服务的实时状态"
                ) {
                    HStack(spacing: 8) {
                        Picker("客户端", selection: $manager.selectedClient) {
                            ForEach(ManagedClient.allCases) { client in
                                Label(client.title, systemImage: client.icon).tag(client)
                            }
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                        .frame(width: 190)

                        Button(action: manager.openDataDir) {
                            Label("数据目录", systemImage: "folder")
                        }
                        .buttonStyle(.bordered)

                        Button(action: manager.refreshStatus) {
                            Image(systemName: "arrow.clockwise")
                                .frame(width: 16, height: 16)
                        }
                        .buttonStyle(.bordered)
                        .disabled(manager.selectedIsInstanceStarting || manager.selectedIsInstanceStopping)
                        .help("刷新状态")
                    }
                }

                if !manager.selectedIsInstalled {
                    ClientInstallationNotice(manager: manager)
                }

                DeveloperModeStatusCard(manager: manager)

                HStack(spacing: 12) {
                    StatusCard(
                        title: manager.selectedClient.desktopTitle,
                        subtitle: manager.selectedIsInstalled ? "已安装" : "未安装",
                        icon: "macwindow",
                        color: manager.selectedIsInstalled ? AppTheme.success : AppTheme.danger,
                        detail: manager.selectedIsInstalled ? "应用已就绪" : "请先安装应用"
                    )

                    StatusCard(
                        title: "隔离实例",
                        subtitle: instanceStatusText,
                        icon: manager.selectedIsInstanceStarting || manager.selectedIsInstanceStopping ? "hourglass" : "cpu",
                        color: instanceStatusColor,
                        detail: manager.selectedIsInstanceRunning ? "PID \(manager.selectedInstancePID)" : "等待启动"
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
        if manager.selectedIsInstanceStarting { return "启动中" }
        if manager.selectedIsInstanceStopping { return "停止中" }
        return manager.selectedIsInstanceRunning ? "运行中" : "未运行"
    }

    private var instanceStatusColor: Color {
        if manager.selectedIsInstanceStarting || manager.selectedIsInstanceStopping { return AppTheme.warning }
        return manager.selectedIsInstanceRunning ? AppTheme.success : Color.secondary
    }

    private var proxyStatusText: String {
        if manager.activeProfile?.isCcSwitchMode == true { return "CC-Switch" }
        if manager.activeProfile?.isDirectMode == true { return "直连" }
        return manager.selectedIsProxyRunning ? "运行中" : "未运行"
    }

    private var proxyStatusColor: Color {
        if manager.activeProfile?.isCcSwitchMode == true || manager.activeProfile?.isDirectMode == true { return AppTheme.info }
        return manager.selectedIsProxyRunning ? AppTheme.success : Color.secondary
    }

    private var proxyDetail: String {
        if let profile = manager.activeProfile, profile.isCcSwitchMode {
            return profile.effectiveCcSwitchUrl
        }
        if let profile = manager.activeProfile, profile.isDirectMode {
            return profile.effectiveApiBaseUrl
        }
        return "本地端口 \(manager.selectedProxyPort)"
    }
}

struct ClientInstallationNotice: View {
    @ObservedObject var manager: ClaudexDualManager

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 22, weight: .semibold))
                .foregroundColor(AppTheme.danger)

            VStack(alignment: .leading, spacing: 4) {
                Text("需要先安装 \(manager.selectedClient.desktopTitle)")
                    .font(.system(size: 14, weight: .bold))
                Text("未在“应用程序”文件夹中检测到客户端，安装完成后请重新检测。")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }

            Spacer()

            Button("重新检测", action: manager.refreshStatus)
                .buttonStyle(.bordered)

            Button("前往下载", action: manager.openSelectedDownloadPage)
                .buttonStyle(.borderedProminent)
        }
        .padding(16)
        .appCard(borderColor: AppTheme.danger.opacity(0.35))
    }
}

// MARK: - Active Profile Card

struct ActiveProfileCard: View {
    let profile: ConfigProfile
    @ObservedObject var manager: ClaudexDualManager
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
                    ProfileInfoBlock(
                        label: "代理模式",
                        value: profile.isCcSwitchMode ? "CC Switch" : (profile.isDirectMode ? "直连" : "本地代理")
                    )
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
        if manager.selectedIsInstanceRunning || manager.selectedIsInstanceStopping {
            CompactActionButton(
                title: manager.selectedIsInstanceStopping ? "停止中" : "停止",
                icon: manager.selectedIsInstanceStopping ? "hourglass" : "stop.fill",
                color: AppTheme.danger,
                isDestructive: true,
                isLoading: manager.selectedIsInstanceStopping,
                disabled: !manager.selectedIsInstanceRunning || manager.selectedIsInstanceStarting || manager.selectedIsInstanceStopping
            ) {
                Task { await manager.stopInstance() }
            }
        } else {
            CompactActionButton(
                title: manager.selectedIsInstanceStarting ? "启动中" : "启动",
                icon: manager.selectedIsInstanceStarting ? "hourglass" : "play.fill",
                color: AppTheme.ink,
                isLoading: manager.selectedIsInstanceStarting,
                disabled: manager.selectedIsInstanceStarting || manager.selectedIsInstanceStopping || !manager.selectedIsInstalled || !manager.selectedIsEnvironmentReady
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
    @ObservedObject var manager: ClaudexDualManager

    private var statusColor: Color {
        manager.selectedIsEnvironmentReady ? AppTheme.success : AppTheme.warning
    }

    var body: some View {
        HStack(spacing: 16) {
            ZStack {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(statusColor.opacity(0.12))
                Image(systemName: manager.selectedIsEnvironmentReady ? "checkmark.shield.fill" : "hammer.fill")
                    .font(.system(size: 23, weight: .semibold))
                    .foregroundColor(statusColor)
            }
            .frame(width: 54, height: 54)

            VStack(alignment: .leading, spacing: 5) {
                Text(manager.selectedClient == .claude ? "开发者模式" : "隔离环境")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.secondary)
                Text(manager.selectedIsEnvironmentReady ? "环境已就绪" : "需要初始化")
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                Text(manager.selectedIsConfigured ? "第三方模型配置已就绪，可直接启动隔离实例" : "创建隔离数据目录并初始化网关配置")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }

            Spacer()

            Button(action: manager.enableDeveloperMode) {
                Label(manager.selectedIsEnvironmentReady ? "已就绪" : "一键初始化", systemImage: manager.selectedIsEnvironmentReady ? "checkmark" : "power")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(.white)
                    .frame(width: 120, height: 40)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(manager.selectedIsEnvironmentReady ? statusColor.opacity(0.68) : AppTheme.ink)
                    )
            }
            .buttonStyle(.plain)
            .disabled(manager.selectedIsEnvironmentReady || manager.selectedIsInstanceStarting || manager.selectedIsInstanceStopping)
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
    @ObservedObject var manager: ClaudexDualManager
    @State private var selectedProfileId: UUID?
    @State private var isNewProfile = false

    var selectedProfile: ConfigProfile? {
        manager.sharedProfiles.first { $0.id == selectedProfileId }
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
                        Text("\(manager.sharedProfiles.count) 个配置")
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
                        ForEach(manager.sharedProfiles) { profile in
                            ProfileRow(
                                profile: profile,
                                isActive: manager.sharedActiveProfileId == profile.id,
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
                                        selectedProfileId = manager.sharedProfiles.first?.id
                                    }
                                }
                                .disabled(manager.sharedProfiles.count <= 1)
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
                            allowedHosts: newProfile.allowedHosts,
                            proxyMode: newProfile.proxyMode,
                            ccSwitchUrl: newProfile.ccSwitchUrl,
                            claudeApiBaseUrl: newProfile.claudeApiBaseUrl,
                            codexApiBaseUrl: newProfile.codexApiBaseUrl
                        )
                        manager.activateProfile(id: profile.id)
                        isNewProfile = false
                        selectedProfileId = profile.id
                    },
                    onCancel: {
                        isNewProfile = false
                        selectedProfileId = manager.sharedProfiles.first?.id
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
                            ccSwitchUrl: updated.ccSwitchUrl,
                            claudeApiBaseUrl: updated.claudeApiBaseUrl,
                            codexApiBaseUrl: updated.codexApiBaseUrl
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
                selectedProfileId = manager.sharedActiveProfileId ?? manager.sharedProfiles.first?.id
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
                    Text(profile.isCcSwitchMode ? "CC Switch" : (profile.isDirectMode ? "直连" : profile.effectiveUpstreamModel))
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
    @ObservedObject var manager: ClaudexDualManager
    let profile: ConfigProfile?
    let onSave: (ConfigProfile) -> Void
    let onCancel: (() -> Void)?

    @State private var name: String = ""
    @State private var claudeApiBaseUrl: String = ""
    @State private var codexApiBaseUrl: String = ""
    @State private var apiKey: String = ""
    @State private var authScheme: String = "bearer"
    @State private var modelName: String = ""
    @State private var allowedHosts: String = ""
    @State private var claudeProxyPort: String = ""
    @State private var codexProxyPort: String = ""
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
        .onChange(of: proxyMode) { newMode in
            if newMode == "direct" {
                authScheme = "bearer"
            }
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
                    Text("直连").tag("direct")
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }

            modeFields
            ConfigField(title: "出站主机白名单", prompt: "* 表示允许所有，多个用逗号分隔", text: $allowedHosts)
            Text("同一配置同时供 Claude 和 Codex 使用；Codex 上游需兼容 OpenAI Responses API。")
                .font(.system(size: 11))
                .foregroundColor(AppTheme.muted)
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
            ConfigField(
                title: "Claude API Base URL（Anthropic）",
                prompt: "https://api.example.com/apps/anthropic",
                text: $claudeApiBaseUrl
            )
            ConfigField(
                title: "Codex API Base URL（OpenAI）",
                prompt: "https://api.example.com/v1",
                text: $codexApiBaseUrl
            )
            Text("Claude 使用 /v1/messages，Codex 使用 /v1/responses；两个端点必须分别兼容对应协议。")
                .font(.system(size: 11))
                .foregroundColor(AppTheme.muted)
            apiKeyField
            authSchemeField
            ConfigField(
                title: "上游模型名称",
                prompt: ConfigProfile.defaultUpstreamModel,
                text: $modelName
            )
            if proxyMode == "localProxy" {
                proxyPortField
            }
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
                if proxyMode == "localProxy" {
                    Text("x-api-key").tag("x-api-key")
                    Text("anthropic-api-key").tag("anthropic-api-key")
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
        }
    }

    private var proxyPortField: some View {
        VStack(alignment: .leading, spacing: 6) {
            fieldLabel("本地代理端口")
            HStack {
                Text("Claude")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(AppTheme.inkSecondary)
                TextField("3456", text: $claudeProxyPort)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 84)
                Text("Codex")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(AppTheme.inkSecondary)
                TextField("3460", text: $codexProxyPort)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 84)
                Spacer()
            }
            Text("共享同一套推理配置，两个运行实例使用独立本地端口。")
                .font(.system(size: 11))
                .foregroundColor(AppTheme.muted)
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
        let isCurrent = manager.sharedActiveProfileId == profile.id
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
            .disabled(manager.sharedProfiles.count <= 1)
        }
    }

    private func loadProfile() {
        if let p = profile {
            name = p.name
            claudeApiBaseUrl = p.effectiveClaudeApiBaseUrl
            codexApiBaseUrl = p.effectiveCodexApiBaseUrl
            apiKey = manager.apiKey(for: p)
            authScheme = p.effectiveAuthScheme
            modelName = p.effectiveUpstreamModel
            allowedHosts = p.allowedHosts
            proxyMode = p.effectiveProxyMode
            ccSwitchUrl = p.effectiveCcSwitchUrl
        } else {
            name = ""
            claudeApiBaseUrl = ""
            codexApiBaseUrl = ""
            apiKey = ""
            authScheme = "bearer"
            modelName = ConfigProfile.defaultUpstreamModel
            allowedHosts = "*"
            proxyMode = "localProxy"
            ccSwitchUrl = ConfigProfile.defaultCcSwitchUrl
        }
        claudeProxyPort = String(manager.proxyPort)
        codexProxyPort = String(manager.codexProxyPort)
    }

    private func save() {
        // Update global proxy port if changed (only relevant for localProxy mode)
        if proxyMode == "localProxy" {
            if let newClaudePort = Int(claudeProxyPort), newClaudePort > 1024 && newClaudePort < 65535, newClaudePort != manager.proxyPort {
                manager.setProxyPort(newClaudePort, for: .claude)
            }
            if let newCodexPort = Int(codexProxyPort), newCodexPort > 1024 && newCodexPort < 65535, newCodexPort != manager.codexProxyPort {
                manager.setProxyPort(newCodexPort, for: .codex)
            }
        }

        let updated = ConfigProfile(
            id: profile?.id ?? UUID(),
            name: name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "未命名配置" : name.trimmingCharacters(in: .whitespacesAndNewlines),
            // Keep Claude's endpoint in the legacy field so older builds can
            // still open a newly saved profile.
            apiBaseUrl: claudeApiBaseUrl.trimmingCharacters(in: .whitespacesAndNewlines),
            apiKey: apiKey.trimmingCharacters(in: .whitespacesAndNewlines),
            authScheme: authScheme,
            modelName: modelName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? ConfigProfile.defaultUpstreamModel : modelName,
            allowedHosts: allowedHosts.trimmingCharacters(in: .whitespacesAndNewlines),
            proxyMode: proxyMode,
            ccSwitchUrl: ccSwitchUrl.trimmingCharacters(in: .whitespacesAndNewlines),
            claudeApiBaseUrl: claudeApiBaseUrl.trimmingCharacters(in: .whitespacesAndNewlines),
            codexApiBaseUrl: codexApiBaseUrl.trimmingCharacters(in: .whitespacesAndNewlines),
            client: nil
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
    @ObservedObject var updateManager: AppUpdateManager
    private let authorURL = URL(string: "https://www.xiaohongshu.com/user/profile/588f4a595e87e7481d7b0c75")!
    private let appVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
    private let buildNumber = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
    private let releaseTime = Bundle.main.object(forInfoDictionaryKey: "ClaudeDualReleaseTime") as? String ?? "-"

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                PageHeader(
                    eyebrow: "应用信息",
                    title: "关于 ClaudexDual",
                    subtitle: "统一管理 Claude 与 Codex 隔离实例的第三方模型工具"
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
                        Text("ClaudexDual")
                            .font(.system(size: 26, weight: .bold, design: .rounded))
                        Text("让 Claude 与 Codex 自由连接你的模型服务")
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
                    AboutInfoRow(label: "数据目录", value: "~/Library/Application Support/ClaudeDual")
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

                    UpdateStatusCard(updateManager: updateManager)
                        .frame(maxWidth: 520)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
            }
            .padding(28)
        }
    }
}

struct UpdateStatusCard: View {
    @ObservedObject var updateManager: AppUpdateManager

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                Image(systemName: statusIcon)
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundColor(statusColor)

                VStack(alignment: .leading, spacing: 3) {
                    Text("在线升级")
                        .font(.system(size: 14, weight: .bold))
                    Text(updateManager.statusMessage)
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }

                Spacer()

                if updateManager.isChecking {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Button("检查更新") {
                        Task { _ = await updateManager.checkForUpdates() }
                    }
                    .buttonStyle(.bordered)
                }
            }

            if let errorMessage = updateManager.errorMessage {
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                        .font(.system(size: 11))
                        .foregroundColor(AppTheme.danger)
                    Spacer()
                    Button("打开 Releases", action: updateManager.openReleasePage)
                        .buttonStyle(.link)
                }
            }

            if let release = updateManager.availableRelease {
                Divider()
                VStack(alignment: .leading, spacing: 6) {
                    Text(release.title)
                        .font(.system(size: 13, weight: .semibold))
                    Text(release.notes)
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                        .lineLimit(5)
                        .textSelection(.enabled)
                }

                HStack {
                    Button("查看 Release", action: updateManager.openReleasePage)
                        .buttonStyle(.link)
                    Spacer()
                    Button {
                        Task { await updateManager.downloadAvailableUpdate() }
                    } label: {
                        if updateManager.isDownloading {
                            HStack(spacing: 7) {
                                ProgressView().controlSize(.small)
                                Text("正在下载…")
                            }
                        } else {
                            Label("下载升级包", systemImage: "arrow.down.circle")
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(updateManager.isDownloading)
                }
            }

            if let installerURL = updateManager.downloadedInstallerURL {
                Divider()
                HStack {
                    Label("已通过 SHA-256 校验", systemImage: "checkmark.seal.fill")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(AppTheme.success)
                    Spacer()
                    Button("重新打开") {
                        NSWorkspace.shared.open(installerURL)
                    }
                    .buttonStyle(.link)
                }
            }
        }
        .padding(16)
        .appCard(cornerRadius: 10)
    }

    private var statusIcon: String {
        if updateManager.errorMessage != nil { return "exclamationmark.triangle.fill" }
        return updateManager.availableRelease == nil ? "checkmark.shield.fill" : "arrow.down.circle.fill"
    }

    private var statusColor: Color {
        if updateManager.errorMessage != nil { return AppTheme.warning }
        return updateManager.availableRelease == nil ? AppTheme.success : AppTheme.focus
    }
}

struct UpdateAvailableSheet: View {
    @ObservedObject var updateManager: AppUpdateManager
    @Binding var isPresented: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: "sparkles.rectangle.stack.fill")
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundColor(AppTheme.focus)
                VStack(alignment: .leading, spacing: 4) {
                    Text("发现 ClaudexDual 新版本")
                        .font(.system(size: 20, weight: .bold))
                    Text(versionSummary)
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
                Spacer()
            }

            if let release = updateManager.availableRelease {
                ScrollView {
                    Text(release.notes)
                        .font(.system(size: 12))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                }
                .frame(height: 180)
                .padding(12)
                .background(AppTheme.surfaceSoft, in: RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(AppTheme.border, lineWidth: 1))
            }

            if let errorMessage = updateManager.errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 11))
                    .foregroundColor(AppTheme.danger)
            } else {
                Text("下载后会校验大小与 SHA-256，随后自动替换应用并重新启动，无需手动拖拽。若自动安装失败，会打开安装包供手动升级。")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }

            HStack {
                Button("稍后") { isPresented = false }
                    .keyboardShortcut(.cancelAction)
                Button("查看 Release", action: updateManager.openReleasePage)
                    .buttonStyle(.link)
                Spacer()
                Button {
                    Task { await updateManager.downloadAvailableUpdate() }
                } label: {
                    if updateManager.isDownloading || updateManager.isInstalling {
                        HStack(spacing: 7) {
                            ProgressView().controlSize(.small)
                            Text(updateManager.isInstalling ? "正在安装…" : "正在下载…")
                        }
                    } else {
                        Label("下载并安装", systemImage: "arrow.down.circle")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(updateManager.isDownloading || updateManager.isInstalling)
            }
        }
        .padding(24)
        .frame(width: 540)
    }

    private var versionSummary: String {
        guard let release = updateManager.availableRelease else { return "" }
        return "当前 v\(updateManager.currentVersion) · 最新 \(release.tagName)"
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
    @ObservedObject var manager: ClaudexDualManager

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            PageHeader(
                eyebrow: "运行记录",
                title: "运行日志",
                subtitle: "追踪实例启动、配置写入与代理服务事件"
            ) {
                HStack(spacing: 9) {
                    Text("\(manager.selectedLogs.count) 条记录")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(AppTheme.surface, in: Capsule())

                    Button(action: manager.clearLogs) {
                        Label("清空", systemImage: "trash")
                    }
                    .buttonStyle(.bordered)
                    .disabled(manager.selectedLogs.isEmpty)
                }
            }

            if manager.selectedLogs.isEmpty {
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
                        ForEach(Array(manager.selectedLogs.enumerated()), id: \.element.id) { index, entry in
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
