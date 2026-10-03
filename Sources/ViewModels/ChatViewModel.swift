import Foundation
import SwiftUI
import Combine

@MainActor
public final class ChatViewModel: ObservableObject, ACPClientDelegate {
    @Published public var sessions: [ChatSession] = []
    @Published public var selectedSessionId: UUID?
    @Published public var connectionStatus: ServerConnectionStatus = .disconnected
    @Published public var inputText: String = ""
    @Published public var isGenerating: Bool = false
    @Published public var telemetryLogs: [String] = []
    @Published public var activeAuthURL: URL? = nil

    private var client: ACPClient?
    private let settings = SettingsManager.shared
    private var thinkingTimer: AnyCancellable?

    public init() {
        createInitialSession()
        Task {
            await reconnect()
        }
    }

    public var activeSession: ChatSession? {
        get {
            guard let id = selectedSessionId else { return sessions.first }
            return sessions.first(where: { $0.id == id })
        }
        set {
            guard let newValue = newValue, let idx = sessions.firstIndex(where: { $0.id == newValue.id }) else { return }
            sessions[idx] = newValue
        }
    }

    // MARK: - Session Management

    public func createInitialSession() {
        if sessions.isEmpty {
            let session = ChatSession(
                title: "New Chat",
                mode: settings.defaultMode,
                modelId: settings.defaultModel,
                reasoningEffort: settings.defaultEffort,
                workspacePath: settings.resolvedWorkingDirectory
            )
            sessions.append(session)
            selectedSessionId = session.id
        }
    }

    public func newSession() {
        let session = ChatSession(
            title: "New Chat",
            mode: settings.defaultMode,
            modelId: settings.defaultModel,
            reasoningEffort: settings.defaultEffort,
            workspacePath: settings.resolvedWorkingDirectory
        )
        sessions.insert(session, at: 0)
        selectedSessionId = session.id

        Task {
            await initializeServerSession(for: session.id)
        }
    }

    public func selectSession(_ id: UUID) {
        selectedSessionId = id
        if let session = sessions.first(where: { $0.id == id }), session.serverSessionId == nil, client?.isConnected == true {
            Task { await initializeServerSession(for: id) }
        }
    }

    public func deleteSession(_ id: UUID) {
        sessions.removeAll(where: { $0.id == id })
        if selectedSessionId == id {
            selectedSessionId = sessions.first?.id
        }
        if sessions.isEmpty {
            newSession()
        }
    }

    // MARK: - Client & Transport Lifecycle

    public func reconnect() async {
        await client?.disconnect()
        // Server session IDs are scoped to their transport/server process.
        for index in sessions.indices {
            sessions[index].serverSessionId = nil
        }

        let transport: any ACPTransport
        switch settings.transportMode {
        case .subprocess:
            transport = ACPSubprocessManager(
                strategy: settings.subprocessStrategy,
                customPath: settings.customBinaryPath,
                nodePath: settings.nodePath,
                pnpmPath: settings.pnpmPath,
                customArgs: settings.customArgs,
                workingDirectory: settings.resolvedWorkingDirectory,
                traceLogging: settings.traceLogging
            )
        case .websocket:
            if let url = settings.webSocketURL {
                transport = ACPWebSocketClient(url: url)
            } else {
                connectionStatus = .error("Invalid WebSocket URL")
                return
            }
        case .mock:
            transport = ACPMockClient()
        }

        let newClient = ACPClient(transport: transport)
        newClient.delegate = self
        self.client = newClient

        do {
            try await newClient.connect()
            if let active = activeSession {
                await initializeServerSession(for: active.id)
            }
        } catch {
            connectionStatus = .error(error.localizedDescription)
        }
    }

    private func initializeServerSession(for sessionId: UUID) async {
        guard let client = client, client.isConnected else { return }
        guard let idx = sessions.firstIndex(where: { $0.id == sessionId }) else { return }

        if sessions[idx].workspacePath.isEmpty || sessions[idx].workspacePath == "/" {
            sessions[idx].workspacePath = settings.resolvedWorkingDirectory
        }
        let s = sessions[idx]
        do {
            let serverId = try await client.createSession(
                cwd: s.workspacePath,
                model: s.modelId,
                mode: s.mode,
                systemPrompt: settings.customSystemPrompt.isEmpty ? nil : settings.customSystemPrompt
            )
            sessions[idx].serverSessionId = serverId
        } catch {
            appendLog("Error creating server session: \(error.localizedDescription)")
        }
    }

    // MARK: - Prompting & Turn Execution

    public func sendCurrentPrompt() {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isGenerating else { return }
        guard let sId = selectedSessionId, let idx = sessions.firstIndex(where: { $0.id == sId }) else { return }

        inputText = ""

        // Append User Message
        let userMessage = ChatMessage(role: .user, content: text)
        sessions[idx].messages.append(userMessage)

        // Set title if it's the first message
        if sessions[idx].messages.filter({ $0.role == .user }).count == 1 {
            let title = String(text.prefix(36)).trimmingCharacters(in: .whitespacesAndNewlines)
            sessions[idx].title = title.isEmpty ? "New Chat" : title
        }

        // Prepare Assistant Message
        let assistantMessage = ChatMessage(
            role: .assistant,
            content: "",
            thinkingState: ThinkingState(isThinking: true, content: "", startTime: Date()),
            toolCalls: [],
            planSteps: [],
            isStreaming: true
        )
        sessions[idx].messages.append(assistantMessage)
        isGenerating = true

        let currentSession = sessions[idx]
        let validCwd = (currentSession.workspacePath.isEmpty || currentSession.workspacePath == "/")
            ? self.settings.resolvedWorkingDirectory
            : currentSession.workspacePath

        if self.sessions[idx].workspacePath != validCwd {
            self.sessions[idx].workspacePath = validCwd
        }

        Task {
            guard let client = self.client else {
                self.appendAssistantError(sessionId: sId, errorText: "Not connected to an ACP server. Check Preferences → Connection and reconnect.")
                self.isGenerating = false
                return
            }

            var serverId = currentSession.serverSessionId
            if serverId == nil {
                do {
                    serverId = try await client.createSession(
                        cwd: validCwd,
                        model: currentSession.modelId,
                        mode: currentSession.mode,
                        systemPrompt: self.settings.customSystemPrompt.isEmpty ? nil : self.settings.customSystemPrompt
                    )
                    if let newIdx = self.sessions.firstIndex(where: { $0.id == sId }) {
                        self.sessions[newIdx].serverSessionId = serverId
                    }
                } catch {
                    self.appendAssistantError(sessionId: sId, errorText: "Failed to initialize session: \(error.localizedDescription)")
                    self.isGenerating = false
                    return
                }
            }

            do {
                try await client.sendPrompt(
                    sessionId: serverId ?? "default",
                    text: text,
                    model: currentSession.modelId,
                    mode: currentSession.mode,
                    effort: currentSession.reasoningEffort
                )
            } catch {
                // A rejected prompt after an explicit stop is expected; the
                // assistant row was already finalized optimistically above.
                if self.isGenerating {
                    self.appendAssistantError(sessionId: sId, errorText: "Turn failed: \(error.localizedDescription)")
                    self.isGenerating = false
                }
            }
        }
    }

    public func cancelTurn() {
        guard isGenerating else { return }
        let serverId = activeSession?.serverSessionId

        // Stop the UI immediately. Network cancellation is best-effort and must
        // never leave the composer stuck in a loading state if the server hangs.
        isGenerating = false
        finishActiveAssistantMessage(cancelled: true)

        if let serverId {
            Task { try? await client?.cancelTurn(sessionId: serverId) }
        }
    }

    private func appendAssistantError(sessionId: UUID, errorText: String) {
        guard let idx = sessions.firstIndex(where: { $0.id == sessionId }) else { return }
        if let lastIdx = sessions[idx].messages.indices.last, sessions[idx].messages[lastIdx].role == .assistant {
            sessions[idx].messages[lastIdx].content += "\n\n⚠️ **Error:** \(errorText)"
            sessions[idx].messages[lastIdx].isStreaming = false
            sessions[idx].messages[lastIdx].thinkingState?.isThinking = false
        }
    }

    private func finishActiveAssistantMessage(cancelled: Bool) {
        guard let sId = selectedSessionId, let idx = sessions.firstIndex(where: { $0.id == sId }) else { return }
        guard let lastIdx = sessions[idx].messages.indices.last, sessions[idx].messages[lastIdx].role == .assistant else { return }

        sessions[idx].messages[lastIdx].isStreaming = false
        if let start = sessions[idx].messages[lastIdx].thinkingState?.startTime {
            sessions[idx].messages[lastIdx].thinkingState?.durationSeconds = Date().timeIntervalSince(start)
        }
        sessions[idx].messages[lastIdx].thinkingState?.isThinking = false

        if cancelled {
            sessions[idx].messages[lastIdx].content += "\n\n*(Generation stopped by user)*"
        }
        sessions[idx].updatedAt = Date()
    }

    private func appendLog(_ log: String) {
        telemetryLogs.append("[\(Date().formatted(date: .omitted, time: .standard))] \(log)")
        if telemetryLogs.count > 500 {
            telemetryLogs.removeFirst(50)
        }
    }

    // MARK: - ACPClientDelegate

    nonisolated public func clientDidUpdateConnectionStatus(_ status: ServerConnectionStatus) {
        Task { @MainActor in
            self.connectionStatus = status
        }
    }

    nonisolated public func clientDidReceiveThinkingStart() {
        Task { @MainActor in
            guard let sId = self.selectedSessionId, let idx = self.sessions.firstIndex(where: { $0.id == sId }) else { return }
            guard let lastIdx = self.sessions[idx].messages.indices.last, self.sessions[idx].messages[lastIdx].role == .assistant else { return }
            self.sessions[idx].messages[lastIdx].thinkingState = ThinkingState(isThinking: true, content: "", startTime: Date())
        }
    }

    nonisolated public func clientDidReceiveThinkingChunk(_ text: String) {
        Task { @MainActor in
            guard let sId = self.selectedSessionId, let idx = self.sessions.firstIndex(where: { $0.id == sId }) else { return }
            guard let lastIdx = self.sessions[idx].messages.indices.last, self.sessions[idx].messages[lastIdx].role == .assistant else { return }

            if self.sessions[idx].messages[lastIdx].thinkingState == nil {
                self.sessions[idx].messages[lastIdx].thinkingState = ThinkingState(isThinking: true, content: "", startTime: Date())
            }
            self.sessions[idx].messages[lastIdx].thinkingState?.content += text

            if let start = self.sessions[idx].messages[lastIdx].thinkingState?.startTime {
                self.sessions[idx].messages[lastIdx].thinkingState?.durationSeconds = Date().timeIntervalSince(start)
            }
        }
    }

    nonisolated public func clientDidReceiveThinkingEnd() {
        Task { @MainActor in
            guard let sId = self.selectedSessionId, let idx = self.sessions.firstIndex(where: { $0.id == sId }) else { return }
            guard let lastIdx = self.sessions[idx].messages.indices.last, self.sessions[idx].messages[lastIdx].role == .assistant else { return }

            if let start = self.sessions[idx].messages[lastIdx].thinkingState?.startTime {
                self.sessions[idx].messages[lastIdx].thinkingState?.durationSeconds = Date().timeIntervalSince(start)
            }
            self.sessions[idx].messages[lastIdx].thinkingState?.isThinking = false
        }
    }

    nonisolated public func clientDidReceiveTextChunk(_ text: String) {
        Task { @MainActor in
            guard let sId = self.selectedSessionId, let idx = self.sessions.firstIndex(where: { $0.id == sId }) else { return }
            guard let lastIdx = self.sessions[idx].messages.indices.last, self.sessions[idx].messages[lastIdx].role == .assistant else { return }

            // If thinking was still active, mark it finished
            if self.sessions[idx].messages[lastIdx].thinkingState?.isThinking == true {
                self.sessions[idx].messages[lastIdx].thinkingState?.isThinking = false
            }

            self.sessions[idx].messages[lastIdx].content += text
        }
    }

    nonisolated public func clientDidUpdateToolCall(_ toolCall: ToolCallItem) {
        Task { @MainActor in
            guard let sId = self.selectedSessionId, let idx = self.sessions.firstIndex(where: { $0.id == sId }) else { return }
            guard let lastIdx = self.sessions[idx].messages.indices.last, self.sessions[idx].messages[lastIdx].role == .assistant else { return }

            var tool = toolCall
            if let existingIdx = self.sessions[idx].messages[lastIdx].toolCalls.firstIndex(where: { $0.id == tool.id }) {
                let prev = self.sessions[idx].messages[lastIdx].toolCalls[existingIdx]
                tool.startedAt = prev.startedAt
                if tool.status == .success || tool.status == .failure {
                    tool.endedAt = Date()
                    tool.durationMs = Int(Date().timeIntervalSince(prev.startedAt) * 1000)
                }
                self.sessions[idx].messages[lastIdx].toolCalls[existingIdx] = tool
            } else {
                self.sessions[idx].messages[lastIdx].toolCalls.append(tool)
            }
        }
    }

    nonisolated public func clientDidUpdatePlan(_ steps: [PlanStepItem]) {
        Task { @MainActor in
            guard let sId = self.selectedSessionId, let idx = self.sessions.firstIndex(where: { $0.id == sId }) else { return }
            guard let lastIdx = self.sessions[idx].messages.indices.last, self.sessions[idx].messages[lastIdx].role == .assistant else { return }
            self.sessions[idx].messages[lastIdx].planSteps = steps
        }
    }

    nonisolated public func clientDidReceiveUsage(used: Int?, size: Int?) {
        Task { @MainActor in
            guard let sId = self.selectedSessionId, let idx = self.sessions.firstIndex(where: { $0.id == sId }) else { return }
            guard let lastIdx = self.sessions[idx].messages.indices.last, self.sessions[idx].messages[lastIdx].role == .assistant else { return }
            if let used = used {
                self.sessions[idx].messages[lastIdx].thinkingState?.tokenCount = used
            }
        }
    }

    nonisolated public func clientDidRequireAuthentication(url: URL) {
        Task { @MainActor in
            self.activeAuthURL = url
            self.appendLog("[Auth Required] Google Account login URL: \(url.absoluteString)")
        }
    }

    nonisolated public func clientDidCompleteTurn() {
        Task { @MainActor in
            self.isGenerating = false
            self.finishActiveAssistantMessage(cancelled: false)
        }
    }

    nonisolated public func clientDidReceiveStderrLog(_ log: String) {
        Task { @MainActor in
            self.appendLog(log)
        }
    }
}
