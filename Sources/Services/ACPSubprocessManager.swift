import Foundation

/// Manages the lifecycle and I/O communication of the local `refined-antigravity-acp` child process.
public final class ACPSubprocessManager: ACPTransport, @unchecked Sendable {
    private let lock = NSLock()
    private var process: Process?
    private var inputPipe: Pipe?
    private var outputPipe: Pipe?
    private var errorPipe: Pipe?

    private var messageContinuation: AsyncStream<Data>.Continuation?
    private var stderrContinuation: AsyncStream<String>.Continuation?

    private let strategy: SubprocessStrategy
    private let customPath: String
    private let nodePath: String
    private let pnpmPath: String
    private let customArgs: String
    private let workingDirectory: String
    private let traceLogging: Bool

    private var _isRunning: Bool = false

    public var isRunning: Bool {
        lock.withLock { _isRunning }
    }

    public init(
        strategy: SubprocessStrategy = .auto,
        customPath: String = "",
        nodePath: String = "",
        pnpmPath: String = "",
        customArgs: String = "",
        workingDirectory: String = FileManager.default.currentDirectoryPath,
        traceLogging: Bool = true
    ) {
        self.strategy = strategy
        self.customPath = customPath
        self.nodePath = nodePath
        self.pnpmPath = pnpmPath
        self.customArgs = customArgs
        self.workingDirectory = workingDirectory
        self.traceLogging = traceLogging
    }

    public func messageStream() -> AsyncStream<Data> {
        AsyncStream { continuation in
            self.lock.withLock {
                self.messageContinuation = continuation
            }
        }
    }

    public func stderrStream() -> AsyncStream<String> {
        AsyncStream { continuation in
            self.lock.withLock {
                self.stderrContinuation = continuation
            }
        }
    }

    public func start() async throws {
        let alreadyRunning: Bool = lock.withLock {
            if _isRunning { return true }
            return false
        }
        if alreadyRunning { return }

        let newProcess = Process()
        let inPipe = Pipe()
        let outPipe = Pipe()
        let errPipe = Pipe()

        newProcess.standardInput = inPipe
        newProcess.standardOutput = outPipe
        newProcess.standardError = errPipe
        newProcess.currentDirectoryURL = URL(fileURLWithPath: workingDirectory)

        // Resolve executable and arguments based on strategy
        let (execURL, arguments) = try resolveLaunchConfiguration()
        newProcess.executableURL = execURL
        newProcess.arguments = arguments

        // Configure environment
        var env = ProcessInfo.processInfo.environment
        let username = NSUserName()
        var defaultPathEntries = [
            URL(fileURLWithPath: nodePath).deletingLastPathComponent().path,
            URL(fileURLWithPath: pnpmPath).deletingLastPathComponent().path,
            "/opt/homebrew/bin",
            "/usr/local/bin",
            "/usr/bin",
            "/bin",
            "/usr/sbin",
            "/sbin",
            "/Users/\(username)/.nvm/versions/node/v24.18.0/bin",
            "/Users/\(username)/Library/pnpm/bin",
            "/Users/\(username)/.local/bin"
        ]
        defaultPathEntries = defaultPathEntries.filter { !$0.isEmpty && $0 != "." }
        let discoveredPath = defaultPathEntries.joined(separator: ":")

        if let existing = env["PATH"] {
            env["PATH"] = "\(discoveredPath):\(existing)"
        } else {
            env["PATH"] = discoveredPath
        }

        if traceLogging {
            env["REFINED_AGY_TRACE"] = "1"
        }

        newProcess.environment = env

        newProcess.terminationHandler = { [weak self] _ in
            guard let self = self else { return }
            self.lock.withLock {
                self._isRunning = false
                self.messageContinuation?.finish()
                self.stderrContinuation?.finish()
            }
        }

        lock.withLock {
            self.process = newProcess
            self.inputPipe = inPipe
            self.outputPipe = outPipe
            self.errorPipe = errPipe
            self._isRunning = true
        }

        do {
            try newProcess.run()
        } catch {
            lock.withLock {
                self._isRunning = false
                self.process = nil
                self.inputPipe = nil
                self.outputPipe = nil
                self.errorPipe = nil
            }
            throw error
        }

        // Start background readers
        startStdoutReader(pipe: outPipe)
        startStderrReader(pipe: errPipe)
    }

    public func send(data: Data) async throws {
        let pipe: Pipe? = lock.withLock {
            guard _isRunning else { return nil }
            return self.inputPipe
        }

        guard let inPipe = pipe else {
            throw NSError(
                domain: "ACPSubprocessManager",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "Process is not running"]
            )
        }

        var mutableData = data
        if mutableData.last != UInt8(ascii: "\n") {
            mutableData.append(UInt8(ascii: "\n"))
        }

        try inPipe.fileHandleForWriting.write(contentsOf: mutableData)
    }

    public func stop() async {
        let (proc, inPipe): (Process?, Pipe?) = lock.withLock {
            guard _isRunning else { return (nil, nil) }
            self._isRunning = false
            return (self.process, self.inputPipe)
        }

        guard let targetProc = proc else { return }

        // Close write pipe to signal EOF
        try? inPipe?.fileHandleForWriting.close()

        targetProc.terminate()

        // Wait with timeout
        let pid = targetProc.processIdentifier
        Task.detached {
            var counter = 0
            while targetProc.isRunning && counter < 20 {
                try? await Task.sleep(nanoseconds: 100_000_000) // 100ms
                counter += 1
            }
            if targetProc.isRunning {
                kill(pid, SIGKILL)
            }
        }
    }

    // MARK: - Private Launch Resolution

    private func resolveLaunchConfiguration() throws -> (URL, [String]) {
        let pnpmExec = !pnpmPath.isEmpty && FileManager.default.isExecutableFile(atPath: pnpmPath)
            ? pnpmPath
            : (SystemDiagnostics.findExecutable(named: "pnpm") ?? "/usr/local/bin/pnpm")

        switch strategy {
        case .bundled:
            if let bundled = Bundle.main.path(forResource: "refined-antigravity-acp", ofType: nil, inDirectory: "bin") {
                return (URL(fileURLWithPath: bundled), parseCustomArgs())
            }
            throw NSError(
                domain: "ACPSubprocessManager",
                code: -2,
                userInfo: [NSLocalizedDescriptionKey: "Bundled refined-antigravity-acp binary not found in app Resources/bin"]
            )

        case .globalBinary:
            let bin = !customPath.isEmpty ? customPath : (SystemDiagnostics.findExecutable(named: "refined-antigravity-acp") ?? "refined-antigravity-acp")
            return (URL(fileURLWithPath: bin), parseCustomArgs())

        case .pnpmDlx:
            return (URL(fileURLWithPath: pnpmExec), ["dlx", "--yes", "@simonepri/refined-antigravity-acp"] + parseCustomArgs())

        case .customPath:
            guard !customPath.isEmpty else {
                throw NSError(
                    domain: "ACPSubprocessManager",
                    code: -3,
                    userInfo: [NSLocalizedDescriptionKey: "Custom executable path is empty"]
                )
            }
            return (URL(fileURLWithPath: customPath), parseCustomArgs())

        case .auto:
            // Prefer bundled if present
            if let bundled = Bundle.main.path(forResource: "refined-antigravity-acp", ofType: nil, inDirectory: "bin") {
                return (URL(fileURLWithPath: bundled), parseCustomArgs())
            }
            // Next prefer global binary
            if let global = SystemDiagnostics.findExecutable(named: "refined-antigravity-acp") {
                return (URL(fileURLWithPath: global), parseCustomArgs())
            }
            // Next prefer pnpm dlx
            if FileManager.default.isExecutableFile(atPath: pnpmExec) {
                return (URL(fileURLWithPath: pnpmExec), ["dlx", "--yes", "@simonepri/refined-antigravity-acp"] + parseCustomArgs())
            }
            // Fallback: try agy directly
            if let agy = SystemDiagnostics.findExecutable(named: "agy") {
                return (URL(fileURLWithPath: agy), ["acp"] + parseCustomArgs())
            }
            throw NSError(
                domain: "ACPSubprocessManager",
                code: -4,
                userInfo: [NSLocalizedDescriptionKey: "Could not find a valid runtime (pnpm, node, or refined-antigravity-acp)"]
            )
        }
    }

    private func parseCustomArgs() -> [String] {
        // Keep user-supplied arguments intact. `--yes` belongs to pnpm dlx and
        // must appear before the package name, not after it as an ACP argument.
        customArgs.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: " ").map(String.init)
    }

    // MARK: - Output Stream Readers

    private func startStdoutReader(pipe: Pipe) {
        let handle = pipe.fileHandleForReading

        Task.detached { [weak self] in
            var buffer = Data()
            for try await byte in handle.bytes {
                if byte == UInt8(ascii: "\n") {
                    if !buffer.isEmpty {
                        _ = self?.lock.withLock {
                            self?.messageContinuation?.yield(buffer)
                        }
                        buffer.removeAll(keepingCapacity: true)
                    }
                } else {
                    buffer.append(byte)
                }
            }
            if !buffer.isEmpty {
                _ = self?.lock.withLock {
                    self?.messageContinuation?.yield(buffer)
                }
            }
        }
    }

    private func startStderrReader(pipe: Pipe) {
        let handle = pipe.fileHandleForReading

        Task.detached { [weak self] in
            for try await line in handle.bytes.lines {
                if !line.isEmpty {
                    _ = self?.lock.withLock {
                        self?.stderrContinuation?.yield(line)
                    }
                }
            }
        }
    }
}
