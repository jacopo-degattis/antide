import Foundation
#if canImport(AppKit)
import AppKit
#endif

public protocol ACPClientDelegate: AnyObject, Sendable {
    func clientDidUpdateConnectionStatus(_ status: ServerConnectionStatus)
    func clientDidRequireAuthentication(url: URL)
    func clientDidReceiveThinkingStart(serverSessionId: String)
    func clientDidReceiveThinkingChunk(_ text: String, serverSessionId: String)
    func clientDidReceiveThinkingEnd(serverSessionId: String)
    func clientDidReceiveTextChunk(_ text: String, serverSessionId: String)
    func clientDidUpdateToolCall(_ toolCall: ToolCallItem, serverSessionId: String)
    func clientDidUpdatePlan(_ steps: [PlanStepItem], serverSessionId: String)
    func clientDidReceiveUsage(used: Int?, size: Int?, serverSessionId: String)
    func clientDidRequestPermission(_ request: PendingACPApproval)
    func clientDidCompleteTurn(serverSessionId: String)
    func clientDidReceiveStderrLog(_ log: String)
}

public final class ACPClient: @unchecked Sendable {
    private let transport: any ACPTransport
    private let lock = NSLock()
    private var pendingRequests: [String: CheckedContinuation<RawInboundMessage, Error>] = [:]
    private var requestTimeouts: [String: Task<Void, Never>] = [:]
    public weak var delegate: (any ACPClientDelegate)?

    private var listenTask: Task<Void, Never>?
    private var stderrTask: Task<Void, Never>?
    private var activeSessionId: String?
    private var sessionWorkingDirectories: [String: String] = [:]

    public init(transport: any ACPTransport) {
        self.transport = transport
    }

    public var isConnected: Bool {
        transport.isRunning
    }

    public func connect() async throws {
        notifyStatus(.connecting("Starting Transport"))

        // Subscribe before spawning the process/opening the socket so early stderr
        // and the first response cannot be lost to an AsyncStream setup race.
        startInboundListener()
        startStderrListener()

        do {
            try await transport.start()
        } catch {
            listenTask?.cancel()
            stderrTask?.cancel()
            listenTask = nil
            stderrTask = nil
            notifyStatus(.error(error.localizedDescription))
            throw error
        }

        notifyStatus(.connecting("Initializing Protocol"))

        // Handshake. A bounded timeout turns broken launch commands / protocol
        // mismatches into a useful connection error instead of an infinite spinner.
        let initParams = ACPInitializeParams()
        let req = JSONRPCRequest(method: "initialize", params: initParams)
        do {
            let resp = try await sendRequest(req, timeout: .seconds(20))
            if let err = resp.error {
                throw err
            }
            notifyStatus(.connected(description: "ACP Connected"))
        } catch {
            notifyStatus(.error("Initialize failed: \(error.localizedDescription)"))
            throw error
        }
    }

    public func disconnect() async {
        listenTask?.cancel()
        stderrTask?.cancel()
        listenTask = nil
        stderrTask = nil

        await transport.stop()

        let pending = lock.withLock { () -> [CheckedContinuation<RawInboundMessage, Error>] in
            let values = Array(pendingRequests.values)
            pendingRequests.removeAll()
            requestTimeouts.values.forEach { $0.cancel() }
            requestTimeouts.removeAll()
            return values
        }

        for continuation in pending {
            continuation.resume(throwing: NSError(domain: "ACPClient", code: -1, userInfo: [NSLocalizedDescriptionKey: "Disconnected"]))
        }

        notifyStatus(.disconnected)
    }

    public func createSession(
        cwd: String,
        model: String?,
        mode: ExecutionMode?,
        systemPrompt: String?
    ) async throws -> String {
        let validCwd: String
        if cwd.isEmpty || cwd == "/" {
            validCwd = FileManager.default.homeDirectoryForCurrentUser.path
        } else {
            validCwd = cwd
        }

        var metaDict: [String: AnyCodable] = [:]
        if let model = model, !model.isEmpty {
            metaDict["model"] = AnyCodable(model)
        }
        if let systemPrompt = systemPrompt, !systemPrompt.isEmpty {
            metaDict["systemPrompt"] = AnyCodable(systemPrompt)
        }

        let params = ACPSessionNewParams(
            cwd: validCwd,
            mcpServers: [],
            modeId: mode?.rawValue ?? "default",
            meta: metaDict.isEmpty ? nil : metaDict
        )
        let req = JSONRPCRequest(method: "session/new", params: params)
        let resp = try await sendRequest(req, timeout: .seconds(60))

        if let err = resp.error {
            throw err
        }

        // Try decoding sessionId from result
        if let data = try? JSONEncoder().encode(resp.result),
           let res = try? JSONDecoder().decode(ACPSessionNewResult.self, from: data) {
            lock.withLock {
                self.activeSessionId = res.sessionId
                self.sessionWorkingDirectories[res.sessionId] = validCwd
            }
            return res.sessionId
        }

        throw NSError(
            domain: "ACPClient",
            code: -3,
            userInfo: [NSLocalizedDescriptionKey: "ACP session/new returned an invalid response (missing sessionId). Check the server protocol/version and telemetry logs."]
        )
    }

    public func loadSession(
        sessionId: String,
        cwd: String,
        model: String?,
        mode: ExecutionMode?,
        systemPrompt: String?
    ) async throws {
        let workingDirectory = cwd.isEmpty || cwd == "/"
            ? FileManager.default.homeDirectoryForCurrentUser.path
            : cwd
        var meta: [String: AnyCodable] = [:]
        if let model, !model.isEmpty { meta["model"] = AnyCodable(model) }
        if let systemPrompt, !systemPrompt.isEmpty { meta["systemPrompt"] = AnyCodable(systemPrompt) }

        let params = ACPSessionLoadParams(
            sessionId: sessionId,
            cwd: workingDirectory,
            modeId: mode?.rawValue,
            meta: meta.isEmpty ? nil : meta
        )
        let response = try await sendRequest(JSONRPCRequest(method: "session/load", params: params), timeout: .seconds(60))
        if let error = response.error { throw error }
        lock.withLock { sessionWorkingDirectories[sessionId] = workingDirectory }
    }

    public func respondToPermission(_ request: PendingACPApproval, optionId: String) async throws {
        let requestID: Any = request.requestIdIsNumeric
            ? (Int64(request.requestId) as Any? ?? request.requestId)
            : request.requestId
        let payload: [String: Any] = [
            "jsonrpc": "2.0",
            "id": requestID,
            "result": ["outcome": ["outcome": "selected", "optionId": optionId]]
        ]
        let data = try JSONSerialization.data(withJSONObject: payload)
        try await transport.send(data: data)
    }

    public func sendPrompt(
        sessionId: String,
        text: String,
        model: String?,
        mode: ExecutionMode?,
        effort: ReasoningEffort?,
        responseTimeout: Duration = .seconds(300)
    ) async throws {
        let promptParams = ACPSessionPromptParams(
            sessionId: sessionId,
            text: text,
            model: model,
            mode: mode?.rawValue,
            effort: effort?.rawValue
        )
        let req = JSONRPCRequest(method: "session/prompt", params: promptParams)
        let response = try await sendRequest(req, timeout: responseTimeout)
        if let error = response.error { throw error }
        // ACP session/prompt normally responds once the turn completes. A few
        // adapters return an explicit `accepted` acknowledgement and stream the
        // remainder asynchronously; those must be completed by their turn event.
        let wasOnlyAccepted = response.result?.dictionaryValue?["status"]?.stringValue == "accepted"
        if !wasOnlyAccepted {
            delegate?.clientDidCompleteTurn(serverSessionId: sessionId)
        }
    }

    public func cancelTurn(sessionId: String) async throws {
        struct CancelParams: Codable {
            let sessionId: String
        }
        let req = JSONRPCRequest(method: "session/cancel", params: CancelParams(sessionId: sessionId))
        _ = try? await sendRequest(req)
    }

    // MARK: - Private Request / Response Matching

    private func sendRequest<P: Codable & Sendable>(
        _ request: JSONRPCRequest<P>,
        timeout: Duration = .seconds(60)
    ) async throws -> RawInboundMessage {
        let reqData = try JSONEncoder().encode(request)

        return try await withCheckedThrowingContinuation { continuation in
            lock.withLock {
                pendingRequests[request.id] = continuation
                requestTimeouts[request.id] = Task { [weak self] in
                    try? await Task.sleep(for: timeout)
                    guard !Task.isCancelled, let self else { return }
                    let expired = self.lock.withLock { () -> CheckedContinuation<RawInboundMessage, Error>? in
                        self.requestTimeouts.removeValue(forKey: request.id)
                        return self.pendingRequests.removeValue(forKey: request.id)
                    }
                    expired?.resume(throwing: NSError(
                        domain: "ACPClient",
                        code: -2,
                        userInfo: [NSLocalizedDescriptionKey: "ACP request ‘\(request.method)’ timed out after \(timeout)"]
                    ))
                }
            }

            Task {
                do {
                    try await transport.send(data: reqData)
                } catch {
                    let continuation = lock.withLock { () -> CheckedContinuation<RawInboundMessage, Error>? in
                        requestTimeouts.removeValue(forKey: request.id)?.cancel()
                        return pendingRequests.removeValue(forKey: request.id)
                    }
                    continuation?.resume(throwing: error)
                }
            }
        }
    }

    // MARK: - Inbound Stream Processor

    private func startInboundListener() {
        listenTask?.cancel()
        let stream = transport.messageStream()
        listenTask = Task.detached { [weak self] in
            guard let self = self else { return }

            for await data in stream {
                let raw: RawInboundMessage
                do {
                    raw = try JSONDecoder().decode(RawInboundMessage.self, from: data)
                } catch {
                    let preview = String(data: data.prefix(1_000), encoding: .utf8) ?? "<non-UTF8 frame>"
                    self.delegate?.clientDidReceiveStderrLog("ACP message decode failed: \(error.localizedDescription) — \(preview)")
                    continue
                }

                if raw.id != nil, raw.method != nil {
                    await self.handleServerRequest(raw)
                } else if let id = raw.id, !id.isEmpty {
                    let continuation = self.lock.withLock { () -> CheckedContinuation<RawInboundMessage, Error>? in
                        self.requestTimeouts.removeValue(forKey: id)?.cancel()
                        return self.pendingRequests.removeValue(forKey: id)
                    }
                    if let continuation {
                        continuation.resume(returning: raw)
                    } else {
                        self.delegate?.clientDidReceiveStderrLog("Received an unmatched ACP response with id ‘\(id)’")
                    }
                } else if raw.isNotification {
                    await self.handleNotification(raw)
                }
            }
        }
    }

    private func startStderrListener() {
        stderrTask?.cancel()
        let stream = transport.stderrStream()
        stderrTask = Task.detached { [weak self] in
            guard let self = self else { return }
            for await line in stream {
                self.delegate?.clientDidReceiveStderrLog(line)

                // Detect OAuth URL from Google ACP server
                if line.contains("https://accounts.google.com/o/oauth2/v2/auth") {
                    if let range = line.range(of: "https://accounts.google.com/o/oauth2/v2/auth[^ \n\r\t]+", options: .regularExpression),
                       let url = URL(string: String(line[range])) {
                        #if canImport(AppKit)
                        NSWorkspace.shared.open(url)
                        #endif
                        self.delegate?.clientDidRequireAuthentication(url: url)
                    }
                }
            }
        }
    }

    private func handleServerRequest(_ message: RawInboundMessage) async {
        guard let requestID = message.id, let method = message.method else { return }
        if method == "session/request_permission",
           let params = message.params?.dictionaryValue,
           let sessionId = params["sessionId"]?.stringValue {
            let tool = params["toolCall"]?.dictionaryValue ?? [:]
            let options = (params["options"]?.arrayValue ?? []).compactMap { value -> ACPPermissionOption? in
                guard let option = value.dictionaryValue,
                      let optionId = option["optionId"]?.stringValue,
                      let name = option["name"]?.stringValue else { return nil }
                return ACPPermissionOption(optionId: optionId, name: name, kind: option["kind"]?.stringValue)
            }
            let permission = PendingACPApproval(
                requestId: requestID,
                requestIdIsNumeric: message.idIsNumeric,
                serverSessionId: sessionId,
                toolCallId: tool["toolCallId"]?.stringValue ?? params["toolCallId"]?.stringValue,
                title: tool["title"]?.stringValue ?? params["title"]?.stringValue ?? "Allow this action?",
                options: options
            )
            delegate?.clientDidRequestPermission(permission)
            return
        }

        if method == "fs/read_text_file" || method == "fs/write_text_file" {
            await handleFilesystemRequest(message, method: method)
            return
        }

        let requestIdValue: Any = message.idIsNumeric ? (Int64(requestID) as Any? ?? requestID) : requestID
        let payload: [String: Any] = [
            "jsonrpc": "2.0",
            "id": requestIdValue,
            "error": ["code": -32601, "message": "Unsupported ACP client request: \\(method)"]
        ]
        if let data = try? JSONSerialization.data(withJSONObject: payload) {
            try? await transport.send(data: data)
        }
        delegate?.clientDidReceiveStderrLog("Unsupported ACP server request: \\(method)")
    }

    private func handleFilesystemRequest(_ message: RawInboundMessage, method: String) async {
        guard let requestID = message.id,
              let params = message.params?.dictionaryValue,
              let sessionID = params["sessionId"]?.stringValue,
              let path = params["path"]?.stringValue else {
            await sendServerError(id: message.id, numericID: message.idIsNumeric, code: -32602, message: "Invalid filesystem request parameters")
            return
        }

        do {
            let fileURL = try resolveFilesystemURL(path, sessionID: sessionID)
            if method == "fs/read_text_file" {
                let contents = try String(contentsOf: fileURL, encoding: .utf8)
                let selectedContents: String
                if let line = params["line"]?.intValue {
                    let lines = contents.components(separatedBy: .newlines)
                    let start = min(max(0, line - 1), lines.count)
                    let count = max(0, params["limit"]?.intValue ?? (lines.count - start))
                    selectedContents = lines.dropFirst(start).prefix(count).joined(separator: "\\n")
                } else {
                    selectedContents = contents
                }
                await sendServerResult(id: requestID, numericID: message.idIsNumeric, result: ["content": selectedContents])
            } else {
                guard let contents = params["content"]?.stringValue else {
                    await sendServerError(id: message.id, numericID: message.idIsNumeric, code: -32602, message: "Missing text content for fs/write_text_file")
                    return
                }
                try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
                try contents.write(to: fileURL, atomically: true, encoding: .utf8)
                await sendServerResult(id: requestID, numericID: message.idIsNumeric, result: [:])
            }
        } catch {
            delegate?.clientDidReceiveStderrLog("ACP \(method) failed for ‘\(path)’: \(error.localizedDescription)")
            await sendServerError(id: message.id, numericID: message.idIsNumeric, code: -32002, message: error.localizedDescription)
        }
    }

    private func resolveFilesystemURL(_ path: String, sessionID: String) throws -> URL {
        guard let workingDirectory = lock.withLock({ sessionWorkingDirectories[sessionID] }) else {
            throw NSError(domain: "ACPClient", code: -1, userInfo: [NSLocalizedDescriptionKey: "No workspace is registered for ACP session \(sessionID)"])
        }

        let root = URL(fileURLWithPath: workingDirectory, isDirectory: true).standardizedFileURL.resolvingSymlinksInPath()
        let requestedURL = path.hasPrefix("/")
            ? URL(fileURLWithPath: path)
            : root.appendingPathComponent(path)
        let target = requestedURL.standardizedFileURL.resolvingSymlinksInPath()
        let rootPath = root.path.hasSuffix("/") ? root.path : root.path + "/"
        guard target.path.hasPrefix(rootPath), target.path != root.path else {
            throw NSError(domain: "ACPClient", code: -2, userInfo: [NSLocalizedDescriptionKey: "ACP filesystem access is restricted to the selected workspace"])
        }
        return target
    }

    private func sendServerResult(id: String, numericID: Bool, result: [String: Any]) async {
        let requestID: Any = numericID ? (Int64(id) as Any? ?? id) : id
        let payload: [String: Any] = ["jsonrpc": "2.0", "id": requestID, "result": result]
        await sendServerPayload(payload)
    }

    private func sendServerError(id: String?, numericID: Bool, code: Int, message: String) async {
        let requestID: Any
        if let id, numericID, let number = Int64(id) { requestID = number }
        else { requestID = id as Any? ?? NSNull() }
        let payload: [String: Any] = [
            "jsonrpc": "2.0",
            "id": requestID,
            "error": ["code": code, "message": message]
        ]
        await sendServerPayload(payload)
    }

    private func sendServerPayload(_ payload: [String: Any]) async {
        do {
            let data = try JSONSerialization.data(withJSONObject: payload)
            try await transport.send(data: data)
        } catch {
            delegate?.clientDidReceiveStderrLog("Failed to reply to ACP filesystem request: \(error.localizedDescription)")
        }
    }

    private func handleNotification(_ msg: RawInboundMessage) async {
        guard let method = msg.method else { return }

        switch method {
        case "session/update":
            handleSessionUpdate(msg.params)

        default:
            break
        }
    }

    private func handleSessionUpdate(_ params: AnyCodable?) {
        guard let params = params?.dictionaryValue,
              let serverSessionId = params["sessionId"]?.stringValue else { return }
        let dict = params["update"]?.dictionaryValue ?? params
        let updateType = dict["sessionUpdate"]?.stringValue ?? dict["type"]?.stringValue ?? ""

        switch updateType {
        case "thinking_start", "thinking":
            delegate?.clientDidReceiveThinkingStart(serverSessionId: serverSessionId)

        case "thinking_chunk", "agent_thought_chunk":
            if let chunk = textValue(dict["content"]) {
                delegate?.clientDidReceiveThinkingChunk(chunk, serverSessionId: serverSessionId)
            }

        case "thinking_end":
            delegate?.clientDidReceiveThinkingEnd(serverSessionId: serverSessionId)

        case "text_chunk", "content", "agent_message_chunk":
            if let chunk = textValue(dict["content"]) {
                delegate?.clientDidReceiveTextChunk(chunk, serverSessionId: serverSessionId)
            }

        case "tool_call", "tool_call_update":
            if let toolDict = dict["toolCall"]?.dictionaryValue {
                parseAndDispatchToolCall(toolDict, serverSessionId: serverSessionId)
            } else {
                parseAndDispatchToolCall(dict, serverSessionId: serverSessionId)
            }

        case "plan":
            let planDict = dict["plan"]?.dictionaryValue ?? dict
            let stepArray = planDict["steps"]?.arrayValue ?? planDict["entries"]?.arrayValue
            if let stepArray {
                let steps = stepArray.enumerated().compactMap { idx, item -> PlanStepItem? in
                    guard let step = item.dictionaryValue else { return nil }
                    let statusText = step["status"]?.stringValue ?? "pending"
                    let status: PlanStepStatus
                    switch statusText {
                    case "completed", "done": status = .completed
                    case "in_progress", "running": status = .running
                    case "failed", "error": status = .failed
                    default: status = .pending
                    }
                    return PlanStepItem(
                        id: step["stepId"]?.stringValue ?? step["id"]?.stringValue ?? "\(idx)",
                        title: step["title"]?.stringValue ?? step["content"]?.stringValue ?? "Task",
                        description: step["description"]?.stringValue,
                        status: status,
                        orderIndex: idx
                    )
                }
                delegate?.clientDidUpdatePlan(steps, serverSessionId: serverSessionId)
            }

        case "usage_update":
            delegate?.clientDidReceiveUsage(
                used: dict["used"]?.intValue,
                size: dict["size"]?.intValue,
                serverSessionId: serverSessionId
            )

        case "turn_completed", "turn_end":
            delegate?.clientDidCompleteTurn(serverSessionId: serverSessionId)

        default:
            if let chunk = textValue(dict["content"]) {
                delegate?.clientDidReceiveTextChunk(chunk, serverSessionId: serverSessionId)
            }
        }
    }

    private func textValue(_ value: AnyCodable?) -> String? {
        guard let value else { return nil }
        if let string = value.stringValue { return string }
        if let object = value.dictionaryValue {
            return object["text"]?.stringValue ?? object["content"]?.stringValue
        }
        if let blocks = value.arrayValue {
            return blocks.compactMap { textValue($0) }.joined()
        }
        return nil
    }

    private func parseAndDispatchToolCall(_ dict: [String: AnyCodable], serverSessionId: String) {
        let callId = dict["toolCallId"]?.stringValue ?? UUID().uuidString
        let title = dict["title"]?.stringValue ?? dict["name"]?.stringValue ?? "Tool Call"
        let kind = dict["kind"]?.stringValue ?? "generic"
        let statusStr = dict["status"]?.stringValue ?? "running"

        let status: ToolCallStatus
        switch statusStr.lowercased() {
        case "completed", "success": status = .success
        case "failed", "error": status = .failure
        case "pending": status = .pending
        default: status = .running
        }

        var inputStr = ""
        if let input = dict["input"] ?? dict["rawInput"] {
            if let str = input.stringValue {
                inputStr = str
            } else if let subDict = input.dictionaryValue {
                if let cmd = subDict["command"]?.stringValue {
                    inputStr = cmd
                } else if let path = subDict["path"]?.stringValue {
                    inputStr = path
                } else if let json = try? JSONSerialization.data(withJSONObject: subDict.mapValues { $0.value.base }, options: [.prettyPrinted]),
                          let formatted = String(data: json, encoding: .utf8) {
                    inputStr = formatted
                }
            }
        }

        var outputStr: String?
        if let output = dict["output"] ?? dict["rawOutput"] {
            if let str = output.stringValue {
                outputStr = str
            } else if let subDict = output.dictionaryValue {
                if let stdout = subDict["stdout"]?.stringValue {
                    outputStr = stdout
                } else if let json = try? JSONSerialization.data(withJSONObject: subDict.mapValues { $0.value.base }, options: [.prettyPrinted]),
                          let formatted = String(data: json, encoding: .utf8) {
                    outputStr = formatted
                }
            }
        }

        let item = ToolCallItem(
            id: callId,
            name: title,
            kind: kind,
            status: status,
            inputFormatted: inputStr,
            outputFormatted: outputStr,
            errorMessage: dict["error"]?.stringValue
        )

        delegate?.clientDidUpdateToolCall(item, serverSessionId: serverSessionId)
    }

    private func notifyStatus(_ status: ServerConnectionStatus) {
        delegate?.clientDidUpdateConnectionStatus(status)
    }
}
