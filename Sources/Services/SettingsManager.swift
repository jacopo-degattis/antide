import Foundation
import SwiftUI

public enum TransportMode: String, CaseIterable, Identifiable {
    case subprocess = "subprocess"
    case websocket = "websocket"
    case mock = "mock"

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .subprocess: return "Local Subprocess (Stdio)"
        case .websocket: return "Remote WebSocket Server"
        case .mock: return "Interactive Demo Mode (Mock)"
        }
    }
}

public enum SubprocessStrategy: String, CaseIterable, Identifiable {
    case auto = "auto"
    case bundled = "bundled"
    case globalBinary = "global_binary"
    case pnpmDlx = "pnpm_dlx"
    case customPath = "custom_path"

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .auto: return "Automatic (Auto-Detect)"
        case .bundled: return "Bundled App Binary"
        case .globalBinary: return "Global refined-antigravity-acp"
        case .pnpmDlx: return "pnpm dlx @simonepri/refined-antigravity-acp"
        case .customPath: return "Custom Command / Script"
        }
    }
}

@MainActor
public final class SettingsManager: ObservableObject {
    public static let shared = SettingsManager()

    // MARK: - App Storage Keys
    @AppStorage("transportMode") public var transportMode: TransportMode = .subprocess
    @AppStorage("subprocessStrategy") public var subprocessStrategy: SubprocessStrategy = .auto
    @AppStorage("customBinaryPath") public var customBinaryPath: String = ""
    @AppStorage("nodePath") public var nodePath: String = ""
    @AppStorage("pnpmPath") public var pnpmPath: String = ""
    @AppStorage("customArgs") public var customArgs: String = ""
    @AppStorage("workingDirectory") public var workingDirectory: String = FileManager.default.currentDirectoryPath
    @AppStorage("traceLogging") public var traceLogging: Bool = true

    // WebSocket Configuration
    @AppStorage("wsHost") public var wsHost: String = "127.0.0.1"
    @AppStorage("wsPort") public var wsPort: Int = 3000
    @AppStorage("wsPath") public var wsPath: String = "/acp"
    @AppStorage("wsUseSSL") public var wsUseSSL: Bool = false

    // Agent Defaults
    @AppStorage("defaultModel") public var defaultModel: String = "gemini-3.1-pro"
    @AppStorage("defaultEffort") public var defaultEffort: ReasoningEffort = .high
    @AppStorage("customSystemPrompt") public var customSystemPrompt: String = ""

    public var resolvedWorkingDirectory: String {
        let trimmed = workingDirectory.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty || trimmed == "/" {
            return FileManager.default.homeDirectoryForCurrentUser.path
        }
        var isDir: ObjCBool = false
        if FileManager.default.fileExists(atPath: trimmed, isDirectory: &isDir), isDir.boolValue {
            return trimmed
        }
        return FileManager.default.homeDirectoryForCurrentUser.path
    }

    private init() {
        if workingDirectory.isEmpty || workingDirectory == "/" {
            workingDirectory = FileManager.default.homeDirectoryForCurrentUser.path
        }
        discoverSystemPaths()
    }

    public func discoverSystemPaths() {
        if nodePath.isEmpty {
            nodePath = SystemDiagnostics.findExecutable(named: "node") ?? "/usr/local/bin/node"
        }
        if pnpmPath.isEmpty {
            pnpmPath = SystemDiagnostics.findExecutable(named: "pnpm") ?? "/usr/local/bin/pnpm"
        }
        if customBinaryPath.isEmpty {
            if let binary = SystemDiagnostics.findExecutable(named: "refined-antigravity-acp") {
                customBinaryPath = binary
            }
        }
    }

    public var webSocketURL: URL? {
        let scheme = wsUseSSL ? "wss" : "ws"
        let pathClean = wsPath.hasPrefix("/") ? wsPath : "/\(wsPath)"
        return URL(string: "\(scheme)://\(wsHost):\(wsPort)\(pathClean)")
    }
}
