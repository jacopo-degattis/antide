import Foundation
import SwiftUI
import Combine

private struct ChatArchive: Codable {
    var sessions: [ChatSession]
    var selectedSessionId: UUID?
}

private struct QueuedTurn {
    let sessionID: UUID
    let text: String
    let model: String
    let effort: ReasoningEffort
}

@MainActor
public final class ChatViewModel: ObservableObject, ACPClientDelegate {
    @Published public var sessions: [ChatSession] = [] {
        didSet { scheduleArchiveWrite() }
    }
    @Published public var workspaces: [Workspace] = []
    @Published public var selectedSessionId: UUID? {
        didSet { scheduleArchiveWrite() }
    }
    @Published public private(set) var generatingSessionIDs: Set<UUID> = []
    @Published public var connectionStatus: ServerConnectionStatus = .disconnected
    @Published public var inputText: String = ""
    @Published public var pendingAttachments: [FileAttachment] = []
    @Published public var telemetryLogs: [String] = []
    @Published public var activeAuthURL: URL? = nil

    private var client: ACPClient?
    private let settings = SettingsManager.shared
    private let workspacesStorageKey = "antide.workspaces"
    private let archiveFileURL: URL
    private let archiveWriteQueue = DispatchQueue(label: "Antide.chat-archive", qos: .utility)
    private var persistenceTask: Task<Void, Never>?
    /// Local chat IDs whose server-side ACP sessions have been loaded on the
    /// currently connected transport.
    private var loadedServerSessions: Set<UUID> = []
    private var sessionInitializationTasks: [UUID: Task<Bool, Never>] = [:]
    /// The bundled Antigravity ACP agent is a single foreground-turn process.
    /// Keep UI conversations independent, but send prompts to that process in a
    /// FIFO so its foreground tool execution cannot cross-wire separate chats.
    private var queuedTurns: [QueuedTurn] = []
    private var activeTurnQueueID: UUID?
    /// Session updates are accepted only after the corresponding prompt has been
    /// sent. `session/load` can replay old transcript events during initialization.
    private var streamingSessionIDs: Set<UUID> = []

    public init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("Antide", isDirectory: true)
        archiveFileURL = appSupport.appendingPathComponent("chats.json")
        workspaces = Self.loadWorkspaces()

        let archive = Self.loadArchive(from: archiveFileURL)
        sessions = archive?.sessions ?? []
        selectedSessionId = archive?.selectedSessionId
        // YOLO is the sole execution mode. Normalize archived sessions created
        // by older versions so they also resume without approval prompts.
        for index in sessions.indices { sessions[index].mode = .yolo }

        // A permission dialog or turn cannot survive the server process. Restore
        // the transcript, but close transient activity indicators cleanly.
        for sessionIndex in sessions.indices {
            for messageIndex in sessions[sessionIndex].messages.indices {
                sessions[sessionIndex].messages[messageIndex].pendingApproval = nil
                if sessions[sessionIndex].messages[messageIndex].isStreaming {
                    sessions[sessionIndex].messages[messageIndex].isStreaming = false
                    sessions[sessionIndex].messages[messageIndex].thinkingState?.isThinking = false
                    sessions[sessionIndex].messages[messageIndex].content += "\n\n*(Antide was closed before this turn finished.)*"
                }
            }
        }

        if sessions.isEmpty {
            createInitialSession()
        } else if selectedSessionId == nil || !sessions.contains(where: { $0.id == selectedSessionId }) {
            selectedSessionId = sessions.first?.id
        }
        scheduleArchiveWrite()

        Task { await reconnect() }
    }

    public var activeSession: ChatSession? {
        get {
            guard let id = selectedSessionId else { return sessions.first }
            return sessions.first(where: { $0.id == id })
        }
        set {
            guard let newValue, let index = sessions.firstIndex(where: { $0.id == newValue.id }) else { return }
            sessions[index] = newValue
        }
    }

    /// The composer and stop control are scoped to the selected chat.
    public var isGenerating: Bool {
        guard let selectedSessionId else { return false }
        return generatingSessionIDs.contains(selectedSessionId)
    }

    public func isGenerating(sessionID: UUID) -> Bool {
        generatingSessionIDs.contains(sessionID)
    }

    // MARK: - Session and workspace management

    public func createInitialSession() {
        guard sessions.isEmpty else { return }
        let session = ChatSession(
            title: "New Chat",
            mode: .yolo,
            modelId: settings.defaultModel,
            reasoningEffort: settings.defaultEffort,
            workspacePath: ""
        )
        sessions.append(session)
        selectedSessionId = session.id
    }

    /// A nil workspace path creates a general chat; a path creates a chat rooted
    /// in that project folder. Every click on a section/project plus creates one
    /// independent ACP session.
    public func newSession(inWorkspacePath workspacePath: String? = nil) {
        let path = workspacePath.map { URL(fileURLWithPath: $0).standardizedFileURL.path } ?? ""
        let session = ChatSession(
            title: "New Chat",
            mode: .yolo,
            modelId: settings.defaultModel,
            reasoningEffort: settings.defaultEffort,
            workspacePath: path
        )
        sessions.insert(session, at: 0)
        selectedSessionId = session.id
    }

    public func selectSession(_ id: UUID) {
        selectedSessionId = id
    }

    public func moveSession(_ id: UUID, toWorkspacePath path: String?) {
        guard let index = sessions.firstIndex(where: { $0.id == id }) else { return }
        let destination = path.map { URL(fileURLWithPath: $0).standardizedFileURL.path } ?? ""
        guard sessions[index].workspacePath != destination else { return }

        if generatingSessionIDs.contains(id) { cancelTurn(for: id) }
        sessionInitializationTasks.removeValue(forKey: id)?.cancel()
        sessions[index].workspacePath = destination
        sessions[index].serverSessionId = nil
        loadedServerSessions.remove(id)
    }

    public func deleteSession(_ id: UUID) {
        let workspacePath = sessions.first(where: { $0.id == id })?.workspacePath ?? ""
        if generatingSessionIDs.contains(id) { cancelTurn(for: id) }
        sessionInitializationTasks.removeValue(forKey: id)?.cancel()
        sessions.removeAll { $0.id == id }
        loadedServerSessions.remove(id)
        if selectedSessionId == id { selectedSessionId = sessions.first?.id }
        if sessions.isEmpty { newSession(inWorkspacePath: workspacePath.isEmpty ? nil : workspacePath) }
    }

    @discardableResult
    public func addWorkspace(at path: String) -> Workspace {
        let normalized = URL(fileURLWithPath: path).standardizedFileURL.path
        if let existing = workspaces.first(where: { $0.path == normalized }) { return existing }
        let workspace = Workspace(path: normalized)
        workspaces.append(workspace)
        persistWorkspaces()
        return workspace
    }

    public func removeWorkspace(_ id: UUID) {
        guard let workspace = workspaces.first(where: { $0.id == id }) else { return }
        workspaces.removeAll { $0.id == id }
        persistWorkspaces()

        for index in sessions.indices where sessions[index].workspacePath == workspace.path {
            let localID = sessions[index].id
            if generatingSessionIDs.contains(localID) { cancelTurn(for: localID) }
            sessionInitializationTasks.removeValue(forKey: localID)?.cancel()
            sessions[index].workspacePath = ""
            sessions[index].serverSessionId = nil
            loadedServerSessions.remove(localID)
        }
    }

    private func persistWorkspaces() {
        guard let data = try? JSONEncoder().encode(workspaces) else { return }
        UserDefaults.standard.set(data, forKey: workspacesStorageKey)
    }

    private static func loadWorkspaces() -> [Workspace] {
        guard let data = UserDefaults.standard.data(forKey: "antide.workspaces"),
              let stored = try? JSONDecoder().decode([Workspace].self, from: data) else { return [] }
        return stored.filter { FileManager.default.fileExists(atPath: $0.path) }
    }

    // MARK: - Persistent chat archive

    private func scheduleArchiveWrite() {
        guard !sessions.isEmpty else { return }
        let archive = ChatArchive(sessions: sessions, selectedSessionId: selectedSessionId)
        persistenceTask?.cancel()
        persistenceTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled, let self,
                  let data = try? JSONEncoder().encode(archive) else { return }
            let destination = self.archiveFileURL
            self.archiveWriteQueue.async {
                do {
                    try Self.writeArchive(data, to: destination)
                } catch {
                    NSLog("Antide: failed to save chat archive: %@", error.localizedDescription)
                }
            }
        }
    }

    nonisolated private static func writeArchive(_ data: Data, to destination: URL) throws {
        try FileManager.default.createDirectory(
            at: destination.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try data.write(to: destination, options: .atomic)
    }

    private static func loadArchive(from url: URL) -> ChatArchive? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(ChatArchive.self, from: data)
    }

    /// Synchronously commits the current transcript when the last app window
    /// closes, in addition to the debounced streaming writes.
    public func flushArchive() {
        persistenceTask?.cancel()
        let archive = ChatArchive(sessions: sessions, selectedSessionId: selectedSessionId)
        do {
            let data = try JSONEncoder().encode(archive)
            let destination = archiveFileURL
            try archiveWriteQueue.sync {
                try Self.writeArchive(data, to: destination)
            }
        } catch {
            appendLog("Failed to save chat archive: \(error.localizedDescription)")
        }
    }

    // MARK: - ACP lifecycle and resumable sessions

    public func reconnect() async {
        for id in Array(generatingSessionIDs) { finishTurn(localSessionID: id, cancelled: true, advanceQueue: false) }
        queuedTurns.removeAll()
        activeTurnQueueID = nil
        for task in sessionInitializationTasks.values { task.cancel() }
        sessionInitializationTasks.removeAll()
        await client?.disconnect()
        loadedServerSessions.removeAll()

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
            guard let url = settings.webSocketURL else {
                connectionStatus = .error("Invalid WebSocket URL")
                return
            }
            transport = ACPWebSocketClient(url: url)
        case .mock:
            transport = ACPMockClient()
        }

        let newClient = ACPClient(transport: transport)
        newClient.delegate = self
        client = newClient

        do {
            try await newClient.connect()
        } catch {
            connectionStatus = .error(error.localizedDescription)
        }
    }

    private func ensureServerSession(for localSessionID: UUID) async -> Bool {
        if loadedServerSessions.contains(localSessionID) { return true }
        if let pending = sessionInitializationTasks[localSessionID] { return await pending.value }

        let task = Task { @MainActor in await self.loadOrCreateServerSession(for: localSessionID) }
        sessionInitializationTasks[localSessionID] = task
        let succeeded = await task.value
        sessionInitializationTasks.removeValue(forKey: localSessionID)
        return succeeded
    }

    private func loadOrCreateServerSession(for localSessionID: UUID) async -> Bool {
        guard let client, client.isConnected,
              let initialIndex = sessions.firstIndex(where: { $0.id == localSessionID }) else { return false }

        let snapshot = sessions[initialIndex]
        let cwd = snapshot.workspacePath.isEmpty ? settings.resolvedWorkingDirectory : snapshot.workspacePath
        let prompt = settings.customSystemPrompt.isEmpty ? nil : settings.customSystemPrompt

        if let serverID = snapshot.serverSessionId {
            do {
                try await client.loadSession(
                    sessionId: serverID,
                    cwd: cwd,
                    model: snapshot.modelId,
                    mode: .yolo,
                    systemPrompt: prompt
                )
                guard let index = sessions.firstIndex(where: { $0.id == localSessionID }),
                      sessions[index].serverSessionId == serverID,
                      sessions[index].workspacePath == snapshot.workspacePath else { return false }
                loadedServerSessions.insert(localSessionID)
                return true
            } catch {
                appendLog("Could not resume \(snapshot.title); creating a fresh ACP session: \(error.localizedDescription)")
                if let index = sessions.firstIndex(where: { $0.id == localSessionID }),
                   sessions[index].serverSessionId == serverID {
                    sessions[index].serverSessionId = nil
                }
            }
        }

        do {
            let serverID = try await client.createSession(
                cwd: cwd,
                model: snapshot.modelId,
                mode: .yolo,
                systemPrompt: prompt
            )
            guard let index = sessions.firstIndex(where: { $0.id == localSessionID }),
                  sessions[index].workspacePath == snapshot.workspacePath else { return false }
            sessions[index].serverSessionId = serverID
            loadedServerSessions.insert(localSessionID)
            return true
        } catch {
            appendLog("Error creating server session: \(error.localizedDescription)")
            return false
        }
    }

    private func localSessionIndex(serverSessionID: String) -> Int? {
        sessions.firstIndex { $0.serverSessionId == serverSessionID }
    }

    // MARK: - Attachment management

    public func addAttachment(_ attach: FileAttachment) {
        pendingAttachments.append(attach)
    }

    public func removeAttachment(_ id: UUID) {
        pendingAttachments.removeAll { $0.id == id }
    }

    public func clearAttachments() {
        pendingAttachments.removeAll()
    }

    // MARK: - Prompting and concurrent turns

    /// Builds the full prompt text by embedding attached file contents before the
    /// user's message text, with clear file markers so the model understands the context.
    private func buildPromptText(_ userText: String, _ attachments: [FileAttachment]) -> String {
        if attachments.isEmpty { return userText }

        var parts: [String] = []
        for attach in attachments {
            let fileContent = attach.content
            if !fileContent.isEmpty {
                parts.append("--- File: \(attach.fileName) (\(attach.formattedSize)) ---")
                parts.append(fileContent)
                parts.append("--- End of \(attach.fileName) ---")
            } else {
                parts.append("[Attached file: \(attach.fileName) (\(attach.formattedSize)) - \(attach.filePath)]")
            }
        }

        if !userText.isEmpty { parts.append(userText) }

        return parts.joined(separator: "\n\n")
    }

    public func sendCurrentPrompt() {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty || !pendingAttachments.isEmpty,
              let localID = selectedSessionId,
              !generatingSessionIDs.contains(localID),
              let index = sessions.firstIndex(where: { $0.id == localID }) else { return }

        let attachments = Array(pendingAttachments)
        inputText = ""
        clearAttachments()

        sessions[index].messages.append(ChatMessage(role: .user, content: text, attachments: attachments))
        if sessions[index].messages.filter({ $0.role == .user }).count == 1 {
            let title = if !text.isEmpty {
                String(text.prefix(36)).trimmingCharacters(in: .whitespacesAndNewlines)
            } else {
                "File: \(attachments.first?.fileName ?? "attachment")"
            }
            sessions[index].title = title.isEmpty ? "New Chat" : title
        }
        sessions[index].updatedAt = Date()
        sessions[index].messages.append(ChatMessage(
            role: .assistant,
            content: "",
            thinkingState: ThinkingState(isThinking: true, content: "", startTime: Date()),
            toolCalls: [],
            planSteps: [],
            isStreaming: true
        ))
        generatingSessionIDs.insert(localID)

        // Build the full prompt text with file contents embedded
        let fullPrompt = buildPromptText(text, attachments)

        let snapshot = sessions[index]
        queuedTurns.append(QueuedTurn(
            sessionID: localID,
            text: fullPrompt,
            model: snapshot.modelId,
            effort: snapshot.reasoningEffort
        ))
        startNextTurnIfNeeded()
    }

    private func startNextTurnIfNeeded() {
        guard activeTurnQueueID == nil else { return }
        while !queuedTurns.isEmpty {
            let turn = queuedTurns.removeFirst()
            guard generatingSessionIDs.contains(turn.sessionID),
                  sessions.contains(where: { $0.id == turn.sessionID }) else { continue }
            activeTurnQueueID = turn.sessionID
            Task { await runTurn(turn) }
            return
        }
    }

    private func runTurn(_ turn: QueuedTurn) async {
        var serverSessionID: String?
        guard let client else {
            failTurn(localSessionID: turn.sessionID, message: "Not connected to an ACP server. Check Connection settings and reconnect.")
            return
        }
        do {
            guard await ensureServerSession(for: turn.sessionID) else {
                failTurn(localSessionID: turn.sessionID, message: "Could not create or resume the ACP session. Check the server logs in Settings → Logs.")
                return
            }
            guard generatingSessionIDs.contains(turn.sessionID),
                  let index = sessions.firstIndex(where: { $0.id == turn.sessionID }),
                  let serverID = sessions[index].serverSessionId else { return }
            serverSessionID = serverID
            streamingSessionIDs.insert(turn.sessionID)
            try await client.sendPrompt(
                sessionId: serverID,
                text: turn.text,
                model: turn.model,
                mode: .yolo,
                effort: turn.effort
            )
        } catch {
            let nsError = error as NSError
            if nsError.domain == "ACPClient", nsError.code == -2, let serverSessionID {
                appendLog("Prompt timed out; cancelling the still-active ACP turn.")
                try? await client.cancelTurn(sessionId: serverSessionID)
            }
            failTurn(localSessionID: turn.sessionID, message: "Turn failed: \(error.localizedDescription)")
        }
    }

    public func cancelTurn() {
        guard let selectedSessionId else { return }
        cancelTurn(for: selectedSessionId)
    }

    private func cancelTurn(for localSessionID: UUID) {
        guard generatingSessionIDs.contains(localSessionID) else { return }
        queuedTurns.removeAll { $0.sessionID == localSessionID }
        let serverID = sessions.first(where: { $0.id == localSessionID })?.serverSessionId
        let isActiveTurn = activeTurnQueueID == localSessionID
        finishTurn(localSessionID: localSessionID, cancelled: true, advanceQueue: !isActiveTurn)

        guard isActiveTurn else { return }
        guard let serverID else {
            activeTurnQueueID = nil
            startNextTurnIfNeeded()
            return
        }
        Task {
            try? await client?.cancelTurn(sessionId: serverID)
            if self.activeTurnQueueID == localSessionID {
                self.activeTurnQueueID = nil
                self.startNextTurnIfNeeded()
            }
        }
    }

    private func failTurn(localSessionID: UUID, message: String) {
        guard generatingSessionIDs.contains(localSessionID) else { return }
        appendAssistantError(sessionId: localSessionID, errorText: message)
        finishTurn(localSessionID: localSessionID, cancelled: false)
    }

    private func appendAssistantError(sessionId: UUID, errorText: String) {
        guard let index = sessions.firstIndex(where: { $0.id == sessionId }),
              let messageIndex = sessions[index].messages.indices.last,
              sessions[index].messages[messageIndex].role == .assistant else { return }
        sessions[index].messages[messageIndex].content += "\n\n⚠️ **Error:** \(errorText)"
        sessions[index].messages[messageIndex].isStreaming = false
        sessions[index].messages[messageIndex].thinkingState?.isThinking = false
    }

    private func finishTurn(localSessionID: UUID, cancelled: Bool, advanceQueue: Bool = true) {
        streamingSessionIDs.remove(localSessionID)
        guard generatingSessionIDs.remove(localSessionID) != nil,
              let index = sessions.firstIndex(where: { $0.id == localSessionID }),
              let messageIndex = sessions[index].messages.indices.last,
              sessions[index].messages[messageIndex].role == .assistant else { return }
        sessions[index].messages[messageIndex].isStreaming = false
        if let start = sessions[index].messages[messageIndex].thinkingState?.startTime {
            sessions[index].messages[messageIndex].thinkingState?.durationSeconds = Date().timeIntervalSince(start)
        }
        sessions[index].messages[messageIndex].thinkingState?.isThinking = false
        if cancelled {
            sessions[index].messages[messageIndex].content += "\n\n*(Generation stopped by user)*"
        }
        sessions[index].updatedAt = Date()
        if advanceQueue, activeTurnQueueID == localSessionID {
            activeTurnQueueID = nil
            startNextTurnIfNeeded()
        }
    }

    private func activeAssistantIndices(serverSessionID: String) -> (session: Int, message: Int)? {
        guard let sessionIndex = localSessionIndex(serverSessionID: serverSessionID),
              activeTurnQueueID == sessions[sessionIndex].id,
              streamingSessionIDs.contains(sessions[sessionIndex].id),
              generatingSessionIDs.contains(sessions[sessionIndex].id),
              let messageIndex = sessions[sessionIndex].messages.indices.last,
              sessions[sessionIndex].messages[messageIndex].role == .assistant else { return nil }
        return (sessionIndex, messageIndex)
    }

    public func respondToPermission(_ request: PendingACPApproval, optionId: String) {
        guard let client else { return }
        Task {
            do {
                try await client.respondToPermission(request, optionId: optionId)
                for sessionIndex in sessions.indices {
                    for messageIndex in sessions[sessionIndex].messages.indices
                    where sessions[sessionIndex].messages[messageIndex].pendingApproval?.requestId == request.requestId {
                        sessions[sessionIndex].messages[messageIndex].pendingApproval = nil
                    }
                }
            } catch {
                appendLog("Failed to send permission response: \(error.localizedDescription)")
            }
        }
    }

    private func appendLog(_ log: String) {
        telemetryLogs.append("[\(Date().formatted(date: .omitted, time: .standard))] \(log)")
        if telemetryLogs.count > 500 { telemetryLogs.removeFirst(50) }
    }

    // MARK: - ACP delegate. Every stream update is routed by server session ID,
    // never by whichever conversation happens to be selected in the UI.

    nonisolated public func clientDidUpdateConnectionStatus(_ status: ServerConnectionStatus) {
        Task { @MainActor in self.connectionStatus = status }
    }

    nonisolated public func clientDidReceiveThinkingStart(serverSessionId: String) {
        Task { @MainActor in
            guard let target = self.activeAssistantIndices(serverSessionID: serverSessionId) else { return }
            self.sessions[target.session].messages[target.message].thinkingState = ThinkingState(isThinking: true, content: "", startTime: Date())
        }
    }

    nonisolated public func clientDidReceiveThinkingChunk(_ text: String, serverSessionId: String) {
        Task { @MainActor in
            guard let target = self.activeAssistantIndices(serverSessionID: serverSessionId) else { return }
            if self.sessions[target.session].messages[target.message].thinkingState == nil {
                self.sessions[target.session].messages[target.message].thinkingState = ThinkingState(isThinking: true, content: "", startTime: Date())
            }
            self.sessions[target.session].messages[target.message].thinkingState?.content += text
        }
    }

    nonisolated public func clientDidReceiveThinkingEnd(serverSessionId: String) {
        Task { @MainActor in
            guard let target = self.activeAssistantIndices(serverSessionID: serverSessionId) else { return }
            let start = self.sessions[target.session].messages[target.message].thinkingState?.startTime
            self.sessions[target.session].messages[target.message].thinkingState?.durationSeconds = start.map { Date().timeIntervalSince($0) }
            self.sessions[target.session].messages[target.message].thinkingState?.isThinking = false
        }
    }

    nonisolated public func clientDidReceiveTextChunk(_ text: String, serverSessionId: String) {
        Task { @MainActor in
            guard let target = self.activeAssistantIndices(serverSessionID: serverSessionId) else { return }
            if self.sessions[target.session].messages[target.message].thinkingState?.isThinking == true {
                self.sessions[target.session].messages[target.message].thinkingState?.isThinking = false
            }
            self.sessions[target.session].messages[target.message].content += text
        }
    }

    nonisolated public func clientDidUpdateToolCall(_ toolCall: ToolCallItem, serverSessionId: String) {
        Task { @MainActor in
            guard let target = self.activeAssistantIndices(serverSessionID: serverSessionId) else { return }
            var tool = toolCall
            let current = self.sessions[target.session].messages[target.message].toolCalls
            if let existingIndex = current.firstIndex(where: { $0.id == tool.id }) {
                let previous = current[existingIndex]
                tool.startedAt = previous.startedAt
                if tool.status == .success || tool.status == .failure {
                    tool.endedAt = Date()
                    tool.durationMs = Int(Date().timeIntervalSince(previous.startedAt) * 1000)
                }
                self.sessions[target.session].messages[target.message].toolCalls[existingIndex] = tool
            } else {
                self.sessions[target.session].messages[target.message].toolCalls.append(tool)
            }
        }
    }

    nonisolated public func clientDidUpdatePlan(_ steps: [PlanStepItem], serverSessionId: String) {
        Task { @MainActor in
            guard let target = self.activeAssistantIndices(serverSessionID: serverSessionId) else { return }
            self.sessions[target.session].messages[target.message].planSteps = steps
        }
    }

    nonisolated public func clientDidReceiveUsage(used: Int?, size: Int?, serverSessionId: String) {
        Task { @MainActor in
            guard let target = self.activeAssistantIndices(serverSessionID: serverSessionId) else { return }
            if let used { self.sessions[target.session].messages[target.message].thinkingState?.tokenCount = used }
        }
    }

    nonisolated public func clientDidRequestPermission(_ request: PendingACPApproval) {
        Task { @MainActor in
            // In YOLO mode, choose an allow option automatically instead of
            // interrupting the turn with an approval card.
            let rankedOptions = request.options.sorted { lhs, rhs in
                Self.permissionOptionRank(lhs) < Self.permissionOptionRank(rhs)
            }
            guard let option = rankedOptions.first else {
                self.appendLog("YOLO could not respond to permission request ‘\(request.title)’: no options were provided.")
                return
            }
            self.respondToPermission(request, optionId: option.optionId)
        }
    }

    private nonisolated static func permissionOptionRank(_ option: ACPPermissionOption) -> Int {
        let kind = option.kind ?? ""
        let description = "\(option.optionId) \(option.name) \(kind)".lowercased()
        if description.contains("allow") || description.contains("approve") || description.contains("accept") {
            return description.contains("always") ? 0 : 1
        }
        if description.contains("reject") || description.contains("deny") || description.contains("cancel") {
            return 3
        }
        return 2
    }

    nonisolated public func clientDidRequireAuthentication(url: URL) {
        Task { @MainActor in
            self.activeAuthURL = url
            self.appendLog("[Auth Required] Google Account login URL: \(url.absoluteString)")
        }
    }

    nonisolated public func clientDidCompleteTurn(serverSessionId: String) {
        Task { @MainActor in
            guard let index = self.localSessionIndex(serverSessionID: serverSessionId) else { return }
            self.finishTurn(localSessionID: self.sessions[index].id, cancelled: false)
        }
    }

    nonisolated public func clientDidReceiveStderrLog(_ log: String) {
        Task { @MainActor in self.appendLog(log) }
    }
}
