import Foundation

public struct DiagnosticItem: Identifiable, Sendable {
    public let id = UUID()
    public let name: String
    public let isAvailable: Bool
    public let path: String?
    public let version: String?
    public let detail: String
}

public struct SystemDiagnostics: Sendable {
    public static func findExecutable(named name: String) -> String? {
        let commonPaths = [
            "/Users/\(NSUserName())/.nvm/versions/node/v24.18.0/bin/\(name)",
            "/Users/\(NSUserName())/Library/pnpm/bin/\(name)",
            "/Users/\(NSUserName())/.local/bin/\(name)",
            "/opt/homebrew/bin/\(name)",
            "/usr/local/bin/\(name)",
            "/usr/bin/\(name)"
        ]

        for path in commonPaths {
            if FileManager.default.isExecutableFile(atPath: path) {
                return path
            }
        }

        // Try `which` command
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        task.arguments = [name]

        var env = ProcessInfo.processInfo.environment
        let extraPaths = "/opt/homebrew/bin:/usr/local/bin:/Users/\(NSUserName())/.nvm/versions/node/v24.18.0/bin:/Users/\(NSUserName())/Library/pnpm/bin:/Users/\(NSUserName())/.local/bin"
        if let currentPath = env["PATH"] {
            env["PATH"] = "\(extraPaths):\(currentPath)"
        } else {
            env["PATH"] = extraPaths
        }
        task.environment = env

        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = Pipe()

        do {
            try task.run()
            task.waitUntilExit()
            if task.terminationStatus == 0 {
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                if let str = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines), !str.isEmpty {
                    return str
                }
            }
        } catch {
            return nil
        }

        return nil
    }

    public static func runDiagnostics() async -> [DiagnosticItem] {
        var items: [DiagnosticItem] = []

        // 1. Check Node.js
        let nodePath = findExecutable(named: "node")
        let nodeVer = nodePath != nil ? getVersion(executable: nodePath!, args: ["--version"]) : nil
        items.append(DiagnosticItem(
            name: "Node.js Runtime",
            isAvailable: nodePath != nil,
            path: nodePath,
            version: nodeVer,
            detail: nodePath != nil ? "Node detected and ready" : "Node.js not found in standard paths"
        ))

        // 2. Check pnpm
        let pnpmPath = findExecutable(named: "pnpm")
        let pnpmVer = pnpmPath != nil ? getVersion(executable: pnpmPath!, args: ["--version"]) : nil
        items.append(DiagnosticItem(
            name: "pnpm Package Manager",
            isAvailable: pnpmPath != nil,
            path: pnpmPath,
            version: pnpmVer,
            detail: pnpmPath != nil ? "pnpm detected (supports zero-install dlx)" : "pnpm not found"
        ))

        // 3. Check agy CLI
        let agyPath = findExecutable(named: "agy")
        let agyVer = agyPath != nil ? getVersion(executable: agyPath!, args: ["--version"]) : nil
        items.append(DiagnosticItem(
            name: "Antigravity CLI (agy)",
            isAvailable: agyPath != nil,
            path: agyPath,
            version: agyVer,
            detail: agyPath != nil ? "Google Antigravity CLI detected" : "agy CLI not found in ~/.local/bin or PATH"
        ))

        // 4. Check refined-antigravity-acp
        let acpPath = findExecutable(named: "refined-antigravity-acp")
        items.append(DiagnosticItem(
            name: "Refined ACP Binary",
            isAvailable: acpPath != nil,
            path: acpPath,
            version: nil,
            detail: acpPath != nil ? "Global wrapper installed" : "Not in global PATH (pnpm dlx or bundled binary will be used)"
        ))

        // 5. Check Bundled Resource
        let bundledPath = Bundle.main.path(forResource: "refined-antigravity-acp", ofType: nil, inDirectory: "bin")
        items.append(DiagnosticItem(
            name: "Bundled Standalone Server",
            isAvailable: bundledPath != nil,
            path: bundledPath,
            version: nil,
            detail: bundledPath != nil ? "Found inside App bundle" : "No embedded binary in Contents/Resources/bin"
        ))

        return items
    }

    private static func getVersion(executable: String, args: [String]) -> String? {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: executable)
        task.arguments = args
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = Pipe()

        do {
            try task.run()
            task.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let out = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
            return out?.isEmpty == false ? out : nil
        } catch {
            return nil
        }
    }
}
