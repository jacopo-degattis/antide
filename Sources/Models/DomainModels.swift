import Foundation

// MARK: - Server Connection State

public enum ServerConnectionStatus: Equatable, Sendable {
    case disconnected
    case connecting(String)
    case connected(description: String)
    case error(String)

    public var isConnected: Bool {
        if case .connected = self { return true }
        return false
    }

    public var displayText: String {
        switch self {
        case .disconnected: return "Disconnected"
        case .connecting(let msg): return "Connecting (\(msg))..."
        case .connected(let desc): return desc
        case .error(let err): return "Error: \(err)"
        }
    }
}

// MARK: - Execution Modes

public enum ExecutionMode: String, CaseIterable, Identifiable, Codable, Sendable {
    case `default` = "default" // Kept for decoding older saved sessions.
    case autoEdit = "auto_edit"
    case yolo = "yolo"
    case plan = "plan"
    case acceptEdits = "accept-edits"

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .default: return "Default"
        case .autoEdit: return "Auto-Edit"
        case .yolo: return "YOLO (Skip Perms)"
        case .plan: return "Plan Only"
        case .acceptEdits: return "Accept Edits"
        }
    }

    public var systemSymbol: String {
        switch self {
        case .default: return "shield.checkered"
        case .autoEdit: return "wand.and.stars"
        case .yolo: return "bolt.shield.fill"
        case .plan: return "list.bullet.clipboard"
        case .acceptEdits: return "checkmark.seal.fill"
        }
    }

    public var description: String {
        switch self {
        case .default: return "Normal mode with standard permission confirmations"
        case .autoEdit: return "Directly modifies workspace files upon approval"
        case .yolo: return "Unattended operations; auto-accepts tool execution and bash commands"
        case .plan: return "Generates structured execution plan without modifying files"
        case .acceptEdits: return "Accepts file edits automatically while asking on commands"
        }
    }
}

// MARK: - Reasoning Effort

public enum ReasoningEffort: String, CaseIterable, Identifiable, Codable, Sendable {
    case low = "low"
    case medium = "medium"
    case high = "high"

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .low: return "Low Effort"
        case .medium: return "Medium Effort"
        case .high: return "High Effort"
        }
    }
}

// MARK: - Model Option

public struct ModelOption: Identifiable, Hashable, Codable, Sendable {
    public let id: String
    public let name: String
    public let provider: String

    public static let standardModels: [ModelOption] = [
        ModelOption(id: "gemini-3.1-pro", name: "Gemini 3.1 Pro (Recommended)", provider: "Google Antigravity"),
        ModelOption(id: "gemini-3.8-flash", name: "Gemini 3.8 Flash (Fast)", provider: "Google Antigravity"),
        ModelOption(id: "claude-3-7-sonnet", name: "Claude 3.7 Sonnet (ACP Proxy)", provider: "Anthropic"),
        ModelOption(id: "gpt-4o", name: "GPT-4o (ACP Proxy)", provider: "OpenAI")
    ]
}

// MARK: - Tool Call Status & Item

public enum ToolCallStatus: String, Codable, Sendable {
    case pending
    case running
    case success
    case failure

    public var iconName: String {
        switch self {
        case .pending: return "clock"
        case .running: return "gearshape.arrow.triangle.2.circlepath"
        case .success: return "checkmark.circle.fill"
        case .failure: return "exclamationmark.triangle.fill"
        }
    }
}

public struct ToolCallItem: Identifiable, Codable, Sendable, Equatable {
    public let id: String
    public var name: String
    public var kind: String // "bash", "edit", "grep", "search", "generic"
    public var status: ToolCallStatus
    public var inputFormatted: String
    public var outputFormatted: String?
    /// Structured file-edit input, rendered with a filename header and source body.
    public var inputFileName: String?
    public var inputFileContent: String?
    public var errorMessage: String?
    public var startedAt: Date
    public var endedAt: Date?
    public var durationMs: Int?

    public init(
        id: String = UUID().uuidString,
        name: String,
        kind: String = "generic",
        status: ToolCallStatus = .running,
        inputFormatted: String = "",
        outputFormatted: String? = nil,
        inputFileName: String? = nil,
        inputFileContent: String? = nil,
        errorMessage: String? = nil,
        startedAt: Date = Date(),
        endedAt: Date? = nil,
        durationMs: Int? = nil
    ) {
        self.id = id
        self.name = name
        self.kind = kind
        self.status = status
        self.inputFormatted = inputFormatted
        self.outputFormatted = outputFormatted
        self.inputFileName = inputFileName
        self.inputFileContent = inputFileContent
        self.errorMessage = errorMessage
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.durationMs = durationMs
    }

    public var sfSymbol: String {
        switch kind.lowercased() {
        case "bash", "terminal", "exec", "command":
            return "terminal.fill"
        case "edit", "file_edit", "write_to_file", "replace_file_content":
            return "doc.badge.gearshape.fill"
        case "read", "view_file", "list_dir":
            return "doc.text.magnifyingglass"
        case "search", "grep_search", "find_by_name":
            return "sparkle.magnifyingglass"
        case "web", "search_web", "read_url_content":
            return "globe"
        default:
            return "cpu.fill"
        }
    }
}

// MARK: - Plan & Steps

public enum PlanStepStatus: String, Codable, Sendable {
    case pending
    case running
    case completed
    case failed

    public var sfSymbol: String {
        switch self {
        case .pending: return "circle.dotted"
        case .running: return "arrow.triangle.2.circlepath.circle.fill"
        case .completed: return "checkmark.circle.fill"
        case .failed: return "xmark.circle.fill"
        }
    }
}

public struct PlanStepItem: Identifiable, Codable, Sendable, Equatable {
    public let id: String
    public var title: String
    public var description: String?
    public var status: PlanStepStatus
    public var orderIndex: Int

    public init(
        id: String = UUID().uuidString,
        title: String,
        description: String? = nil,
        status: PlanStepStatus = .pending,
        orderIndex: Int = 0
    ) {
        self.id = id
        self.title = title
        self.description = description
        self.status = status
        self.orderIndex = orderIndex
    }
}

// MARK: - Thinking State

public struct ThinkingState: Codable, Sendable, Equatable {
    public var isThinking: Bool
    public var content: String
    public var startTime: Date?
    public var durationSeconds: Double?
    public var tokenCount: Int?

    public init(
        isThinking: Bool = false,
        content: String = "",
        startTime: Date? = nil,
        durationSeconds: Double? = nil,
        tokenCount: Int? = nil
    ) {
        self.isThinking = isThinking
        self.content = content
        self.startTime = startTime
        self.durationSeconds = durationSeconds
        self.tokenCount = tokenCount
    }
}

// MARK: - ACP Permission Requests

public struct ACPPermissionOption: Codable, Sendable, Equatable, Identifiable {
    public let optionId: String
    public let name: String
    public let kind: String?

    public var id: String { optionId }
}

public struct PendingACPApproval: Codable, Sendable, Equatable, Identifiable {
    public let requestId: String
    public let requestIdIsNumeric: Bool
    public let serverSessionId: String
    public let toolCallId: String?
    public let title: String
    public let options: [ACPPermissionOption]

    public var id: String { requestId }
}

// MARK: - File Attachment

public struct FileAttachment: Identifiable, Codable, Sendable, Equatable {
    public let id: UUID
    public let fileName: String
    public let filePath: String
    public let mimeType: String
    public let sizeBytes: Int
    /// Text content of the file (for text-based file types)
    public let content: String

    public init(
        id: UUID = UUID(),
        fileName: String,
        filePath: String = "",
        mimeType: String = "application/octet-stream",
        sizeBytes: Int = 0,
        content: String = ""
    ) {
        self.id = id
        self.fileName = fileName
        self.filePath = filePath
        self.mimeType = mimeType
        self.sizeBytes = sizeBytes
        self.content = content
    }

    public var formattedSize: String {
        if sizeBytes < 1024 {
            return "\(sizeBytes) B"
        } else if sizeBytes < 1024 * 1024 {
            let kb = Double(sizeBytes) / 1024.0
            return "\(String(format: "%.1f", kb)) KB"
        } else {
            let mb = Double(sizeBytes) / (1024.0 * 1024.0)
            return "\(String(format: "%.1f", mb)) MB"
        }
    }

    public var iconName: String {
        if mimeType.hasPrefix("image/") {
            return "photo"
        } else if mimeType.hasPrefix("text/") || fileName.hasSuffix(".md") || fileName.hasSuffix(".swift") || fileName.hasSuffix(".py") || fileName.hasSuffix(".js") || fileName.hasSuffix(".ts") || fileName.hasSuffix(".json") {
            return "doc.text"
        } else if mimeType.hasPrefix("application/pdf") {
            return "doc.pdf"
        } else if mimeType.hasPrefix("application/zip") || mimeType.hasPrefix("application/x-tar") || mimeType.hasPrefix("application/gzip") {
            return "folder.zip"
        } else {
            return "doc"
        }
    }
}

// MARK: - Chat Message

public enum MessageRole: String, Codable, Sendable {
    case user
    case assistant
    case system
}

public struct ChatMessage: Identifiable, Codable, Sendable, Equatable {
    public let id: UUID
    public let role: MessageRole
    public let timestamp: Date
    public var content: String
    public var attachments: [FileAttachment]
    public var thinkingState: ThinkingState?
    public var toolCalls: [ToolCallItem]
    public var planSteps: [PlanStepItem]
    public var pendingApproval: PendingACPApproval?
    public var isStreaming: Bool

    public init(
        id: UUID = UUID(),
        role: MessageRole,
        timestamp: Date = Date(),
        content: String = "",
        attachments: [FileAttachment] = [],
        thinkingState: ThinkingState? = nil,
        toolCalls: [ToolCallItem] = [],
        planSteps: [PlanStepItem] = [],
        pendingApproval: PendingACPApproval? = nil,
        isStreaming: Bool = false
    ) {
        self.id = id
        self.role = role
        self.timestamp = timestamp
        self.content = content
        self.attachments = attachments
        self.thinkingState = thinkingState
        self.toolCalls = toolCalls
        self.planSteps = planSteps
        self.pendingApproval = pendingApproval
        self.isStreaming = isStreaming
    }
}

// MARK: - Workspace

public struct Workspace: Identifiable, Codable, Sendable, Equatable {
    public let id: UUID
    public var path: String

    public init(id: UUID = UUID(), path: String) {
        self.id = id
        self.path = URL(fileURLWithPath: path).standardizedFileURL.path
    }

    public var name: String {
        let last = URL(fileURLWithPath: path).lastPathComponent
        return last.isEmpty ? path : last
    }
}

// MARK: - Chat Session

public struct ChatSession: Identifiable, Codable, Sendable, Equatable {
    public let id: UUID
    public var title: String
    public var createdAt: Date
    public var updatedAt: Date
    public var messages: [ChatMessage]
    public var serverSessionId: String?
    public var mode: ExecutionMode
    public var modelId: String
    public var reasoningEffort: ReasoningEffort
    public var workspacePath: String

    public init(
        id: UUID = UUID(),
        title: String = "New Session",
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        messages: [ChatMessage] = [],
        serverSessionId: String? = nil,
        mode: ExecutionMode = .yolo,
        modelId: String = "gemini-3.1-pro",
        reasoningEffort: ReasoningEffort = .high,
        workspacePath: String = FileManager.default.currentDirectoryPath
    ) {
        self.id = id
        self.title = title
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.messages = messages
        self.serverSessionId = serverSessionId
        self.mode = mode
        self.modelId = modelId
        self.reasoningEffort = reasoningEffort
        self.workspacePath = workspacePath
    }
}
