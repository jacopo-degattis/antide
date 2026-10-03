import Foundation

/// High-fidelity simulator transport mimicking `refined-antigravity-acp` for offline testing, UI verification, and demos.
public final class ACPMockClient: ACPTransport, @unchecked Sendable {
    private let lock = NSLock()
    private var messageContinuation: AsyncStream<Data>.Continuation?
    private var stderrContinuation: AsyncStream<String>.Continuation?
    private var _isRunning: Bool = false
    private var activeTurnTask: Task<Void, Never>?

    public var isRunning: Bool {
        lock.withLock { _isRunning }
    }

    public init() {}

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
        lock.withLock {
            _isRunning = true
        }

        lock.withLock {
            stderrContinuation?.yield("[refined-acp] Initialized proxy supervisor (Mock Mode)")
            stderrContinuation?.yield("[refined-acp] Stdio pipeline mounted, watching SQLite checkpoints")
        }
    }

    public func stop() async {
        let task = lock.withLock { () -> Task<Void, Never>? in
            _isRunning = false
            let t = activeTurnTask
            activeTurnTask = nil
            messageContinuation?.finish()
            stderrContinuation?.finish()
            return t
        }
        task?.cancel()
    }

    public func send(data: Data) async throws {
        guard let raw = try? JSONDecoder().decode(RawInboundMessage.self, from: data) else {
            return
        }

        let reqId = raw.id ?? "1"
        let method = raw.method ?? ""

        switch method {
        case "initialize":
            try await Task.sleep(nanoseconds: 80_000_000) // 80ms
            let resp = """
            {"jsonrpc":"2.0","id":"\(reqId)","result":{"protocolVersion":1,"serverInfo":{"name":"refined-antigravity-acp","version":"1.3.0"},"authMethods":[{"id":"google_oauth","name":"Google Account"}]}}
            """
            yieldString(resp)

        case "session/new":
            try await Task.sleep(nanoseconds: 120_000_000) // 120ms
            let resp = """
            {"jsonrpc":"2.0","id":"\(reqId)","result":{"sessionId":"mock-session-\(UUID().uuidString.prefix(8))","models":[{"modelId":"gemini-3.1-pro","name":"Gemini 3.1 Pro"},{"modelId":"gemini-3.8-flash","name":"Gemini 3.8 Flash"}],"modes":[{"modeId":"default","name":"Default"},{"modeId":"yolo","name":"YOLO"}]}}
            """
            yieldString(resp)

        case "session/cancel":
            lock.withLock {
                activeTurnTask?.cancel()
                activeTurnTask = nil
            }
            let resp = """
            {"jsonrpc":"2.0","id":"\(reqId)","result":true}
            """
            yieldString(resp)

        case "session/prompt":
            let resp = """
            {"jsonrpc":"2.0","id":"\(reqId)","result":{"status":"accepted"}}
            """
            yieldString(resp)

            let userPromptText = extractPromptText(from: raw.params)
            startSimulatedAgentTurn(userPrompt: userPromptText)

        default:
            let resp = """
            {"jsonrpc":"2.0","id":"\(reqId)","result":true}
            """
            yieldString(resp)
        }
    }

    private func extractPromptText(from params: AnyCodable?) -> String {
        if let dict = params?.dictionaryValue {
            if let promptList = dict["prompt"]?.arrayValue,
               let first = promptList.first?.dictionaryValue,
               let str = first["text"]?.stringValue {
                return str
            }
            if let str = dict["prompt"]?.stringValue {
                return str
            }
        }
        return "Task"
    }

    private func yieldString(_ str: String) {
        if let d = str.data(using: .utf8) {
            _ = lock.withLock {
                messageContinuation?.yield(d)
            }
        }
    }

    // MARK: - Realistic Agent Turn Simulation

    private func startSimulatedAgentTurn(userPrompt: String) {
        lock.withLock {
            activeTurnTask?.cancel()
        }

        let task = Task.detached { [weak self] in
            guard let self = self else { return }

            // 1. Thinking phase with incremental thoughts
            self.yieldString("""
            {"jsonrpc":"2.0","method":"session/update","params":{"sessionUpdate":"thinking_start"}}
            """)

            let thoughts = [
                "Analyzing request and inspecting project architecture...",
                " Checking local environment and workspace files for relevant context.",
                " Evaluating required tools: planning terminal inspection and verifying configuration.",
                " Synthesizing execution plan for autonomous execution via `agy` CLI."
            ]

            for chunk in thoughts {
                try? await Task.sleep(nanoseconds: 280_000_000)
                if Task.isCancelled { return }
                let escaped = chunk.replacingOccurrences(of: "\"", with: "\\\"")
                self.yieldString("""
                {"jsonrpc":"2.0","method":"session/update","params":{"sessionUpdate":"thinking_chunk","content":"\(escaped)"}}
                """)
            }

            try? await Task.sleep(nanoseconds: 350_000_000)
            self.yieldString("""
            {"jsonrpc":"2.0","method":"session/update","params":{"sessionUpdate":"thinking_end"}}
            """)

            // 2. Structured Plan update
            let planJson = """
            {"jsonrpc":"2.0","method":"session/update","params":{"sessionUpdate":"plan","plan":{"steps":[{"stepId":"1","title":"Analyze project workspace and configuration","status":"completed"},{"stepId":"2","title":"Execute terminal command to verify dependencies","status":"in_progress"},{"stepId":"3","title":"Perform code generation and verify output","status":"pending"}]}}}
            """
            self.yieldString(planJson)

            // 3. Tool Call 1: Terminal bash inspection
            try? await Task.sleep(nanoseconds: 400_000_000)
            let tool1Id = "call_\(UUID().uuidString.prefix(6))"
            self.yieldString("""
            {"jsonrpc":"2.0","method":"session/update","params":{"sessionUpdate":"tool_call","toolCall":{"toolCallId":"\(tool1Id)","title":"Run bash command","kind":"bash","status":"running","input":{"command":"agy --version && git status --short"}}}}
            """)

            try? await Task.sleep(nanoseconds: 700_000_000)
            self.yieldString("""
            {"jsonrpc":"2.0","method":"session/update","params":{"sessionUpdate":"tool_call_update","toolCall":{"toolCallId":"\(tool1Id)","status":"completed","output":{"stdout":"1.2.12\\n M Package.swift\\n?? Sources/UI/ThinkingView.swift"}}}}
            """)

            // 4. Tool Call 2: File reading / grep
            try? await Task.sleep(nanoseconds: 300_000_000)
            let tool2Id = "call_\(UUID().uuidString.prefix(6))"
            self.yieldString("""
            {"jsonrpc":"2.0","method":"session/update","params":{"sessionUpdate":"tool_call","toolCall":{"toolCallId":"\(tool2Id)","title":"Inspect workspace configuration","kind":"search","status":"running","input":{"path":"Sources/AntigravityApp.swift","pattern":"struct AntigravityApp"}}}}
            """)

            try? await Task.sleep(nanoseconds: 500_000_000)
            self.yieldString("""
            {"jsonrpc":"2.0","method":"session/update","params":{"sessionUpdate":"tool_call_update","toolCall":{"toolCallId":"\(tool2Id)","status":"completed","output":{"matches":["@main struct AntigravityApp: App"]}}}}
            """)

            // 5. Update Plan: Mark all completed
            let planComplete = """
            {"jsonrpc":"2.0","method":"session/update","params":{"sessionUpdate":"plan","plan":{"steps":[{"stepId":"1","title":"Analyze project workspace and configuration","status":"completed"},{"stepId":"2","title":"Execute terminal command to verify dependencies","status":"completed"},{"stepId":"3","title":"Perform code generation and verify output","status":"completed"}]}}}
            """
            self.yieldString(planComplete)

            // 6. Stream final response text
            let responseMarkdown = """
            I have analyzed your workspace and connected through `refined-antigravity-acp`.

            ### Execution Summary
            - **Google Antigravity CLI:** Verified (`v1.2.12`)
            - **Transport:** Native Subprocess Stdio with SQLite WAL journal protection
            - **Mode:** Autonomous steering active

            ```swift
            // Subprocess is healthy and responding with NDJSON
            let client = ACPClient(transport: subprocessTransport)
            try await client.connect()
            ```

            You can now send prompts, trigger file edits, and inspect multi-step plans in real time!
            """

            for line in responseMarkdown.split(separator: "\n", omittingEmptySubsequences: false) {
                try? await Task.sleep(nanoseconds: 70_000_000)
                if Task.isCancelled { return }
                let escaped = line
                    .replacingOccurrences(of: "\\", with: "\\\\")
                    .replacingOccurrences(of: "\"", with: "\\\"")
                self.yieldString("""
                {"jsonrpc":"2.0","method":"session/update","params":{"sessionUpdate":"text_chunk","content":"\(escaped)\\n"}}
                """)
            }

            // 7. Finish turn
            try? await Task.sleep(nanoseconds: 100_000_000)
            self.yieldString("""
            {"jsonrpc":"2.0","method":"session/update","params":{"sessionUpdate":"turn_completed"}}
            """)
        }

        lock.withLock {
            self.activeTurnTask = task
        }
    }
}
