import Foundation

// MARK: - JSON-RPC 2.0 Base Types

public struct JSONRPCRequest<P: Codable & Sendable>: Codable, Sendable {
    public let jsonrpc: String
    public let id: String
    public let method: String
    public let params: P?

    public init(id: String = UUID().uuidString, method: String, params: P? = nil) {
        self.jsonrpc = "2.0"
        self.id = id
        self.method = method
        self.params = params
    }
}

public struct JSONRPCNotification<P: Codable & Sendable>: Codable, Sendable {
    public let jsonrpc: String
    public let method: String
    public let params: P?

    public init(method: String, params: P? = nil) {
        self.jsonrpc = "2.0"
        self.method = method
        self.params = params
    }
}

public struct JSONRPCResponse<R: Codable & Sendable>: Codable, Sendable {
    public let jsonrpc: String
    public let id: String?
    public let result: R?
    public let error: JSONRPCError?
}

public struct JSONRPCError: Codable, Sendable, Error, LocalizedError {
    public let code: Int
    public let message: String
    public let data: AnyCodable?

    public var errorDescription: String? {
        "[\(code)] \(message)"
    }
}

// MARK: - Raw Inbound Dispatcher

public struct RawInboundMessage: Codable, Sendable {
    public let jsonrpc: String
    /// JSON-RPC permits string or integer request IDs. Normalize both to strings so
    /// servers implemented in Rust/Go (which commonly use integer IDs) work too.
    public let id: String?
    public let method: String?
    public let params: AnyCodable?
    public let result: AnyCodable?
    public let error: JSONRPCError?

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        jsonrpc = try container.decode(String.self, forKey: .jsonrpc)
        if let stringID = try? container.decode(String.self, forKey: .id) {
            id = stringID
        } else if let integerID = try? container.decode(Int64.self, forKey: .id) {
            id = String(integerID)
        } else {
            id = nil
        }
        method = try container.decodeIfPresent(String.self, forKey: .method)
        params = try container.decodeIfPresent(AnyCodable.self, forKey: .params)
        result = try container.decodeIfPresent(AnyCodable.self, forKey: .result)
        error = try container.decodeIfPresent(JSONRPCError.self, forKey: .error)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(jsonrpc, forKey: .jsonrpc)
        try container.encodeIfPresent(id, forKey: .id)
        try container.encodeIfPresent(method, forKey: .method)
        try container.encodeIfPresent(params, forKey: .params)
        try container.encodeIfPresent(result, forKey: .result)
        try container.encodeIfPresent(error, forKey: .error)
    }

    private enum CodingKeys: String, CodingKey {
        case jsonrpc, id, method, params, result, error
    }

    public var isNotification: Bool {
        id == nil && method != nil
    }

    public var isResponse: Bool {
        id != nil && (result != nil || error != nil)
    }
}

// MARK: - ACP Handshake: initialize

public struct ACPInitializeParams: Codable, Sendable {
    /// ACP uses a numeric protocol version. The previous MCP date string caused
    /// real ACP agents to reject (or never answer) the initialize request.
    public let protocolVersion: Int
    public let clientInfo: ACPClientInfo
    public let clientCapabilities: ACPClientCapabilities

    public init(
        protocolVersion: Int = 1,
        clientInfo: ACPClientInfo = .defaultClient,
        clientCapabilities: ACPClientCapabilities = .defaultCapabilities
    ) {
        self.protocolVersion = protocolVersion
        self.clientInfo = clientInfo
        self.clientCapabilities = clientCapabilities
    }
}

public struct ACPClientInfo: Codable, Sendable {
    public let name: String
    public let version: String

    public static let defaultClient = ACPClientInfo(
        name: "AntigravityCodex",
        version: "1.0.0"
    )
}

public struct ACPClientCapabilities: Codable, Sendable {
    public struct FileSystem: Codable, Sendable {
        public let readTextFile: Bool
        public let writeTextFile: Bool

        public init(readTextFile: Bool = true, writeTextFile: Bool = true) {
            self.readTextFile = readTextFile
            self.writeTextFile = writeTextFile
        }
    }

    public let fs: FileSystem?
    public let terminal: Bool?

    public init(fs: FileSystem? = FileSystem(), terminal: Bool? = true) {
        self.fs = fs
        self.terminal = terminal
    }

    public static let defaultCapabilities = ACPClientCapabilities()
}

public struct ACPInitializeResult: Codable, Sendable {
    public let protocolVersion: Int?
    public let serverInfo: ACPServerInfo?
    public let capabilities: AnyCodable?
    public let authMethods: [ACPAuthMethod]?
}

public struct ACPServerInfo: Codable, Sendable {
    public let name: String
    public let version: String?
}

public struct ACPAuthMethod: Codable, Sendable {
    public let id: String
    public let name: String?
    public let description: String?
}

// MARK: - ACP Session: session/new & session/load

public struct ACPSessionNewParams: Codable, Sendable {
    public let cwd: String
    public let mcpServers: [AnyCodable]
    public let modeId: String?
    public let _meta: [String: AnyCodable]?

    public init(
        cwd: String,
        mcpServers: [AnyCodable] = [],
        modeId: String? = "default",
        meta: [String: AnyCodable]? = nil
    ) {
        self.cwd = cwd
        self.mcpServers = mcpServers
        self.modeId = modeId
        self._meta = meta
    }
}

public struct ACPSessionNewResult: Codable, Sendable {
    public let sessionId: String
    // ACP servers may return model/mode catalogs in their own nested extension
    // shapes. Keep this response minimal so unknown catalog shapes cannot make
    // an otherwise valid `session/new` look like a missing session ID.
}

public struct ACPModelInfo: Codable, Sendable, Identifiable {
    public var id: String { modelId ?? name }
    public let modelId: String?
    public let name: String
    public let description: String?
    public let reasoningEfforts: [String]?
}

public struct ACPModeInfo: Codable, Sendable, Identifiable {
    public var id: String { modeId ?? name }
    public let modeId: String?
    public let name: String
    public let description: String?
}

// MARK: - ACP Prompt: session/prompt

public struct ACPContentBlock: Codable, Sendable {
    public let type: String
    public let text: String

    public init(type: String = "text", text: String) {
        self.type = type
        self.text = text
    }
}

public struct ACPSessionPromptParams: Codable, Sendable {
    public let sessionId: String
    public let prompt: [ACPContentBlock]
    public let _meta: [String: AnyCodable]?

    public init(
        sessionId: String,
        text: String,
        model: String? = nil,
        mode: String? = nil,
        effort: String? = nil
    ) {
        self.sessionId = sessionId
        self.prompt = [ACPContentBlock(type: "text", text: text)]
        var metaDict: [String: AnyCodable] = [:]
        if let model = model { metaDict["model"] = AnyCodable(model) }
        if let mode = mode { metaDict["modeId"] = AnyCodable(mode) }
        if let effort = effort { metaDict["effort"] = AnyCodable(effort) }
        self._meta = metaDict.isEmpty ? nil : metaDict
    }
}

// MARK: - ACP Streaming Updates: session/update notification

public struct ACPSessionUpdateParams: Codable, Sendable {
    public let sessionId: String
    public let sessionUpdate: String?
    public let updateType: String?
    public let content: AnyCodable?
    public let toolCall: ACPToolCallUpdate?
    public let plan: ACPPlanUpdate?
    public let usage: ACPUsageUpdate?

    // Common dynamic payload fallback
    public let data: AnyCodable?
}

public struct ACPToolCallUpdate: Codable, Sendable {
    public let toolCallId: String
    public let title: String?
    public let kind: String?
    public let status: String? // "running", "completed", "failed", "pending"
    public let input: AnyCodable?
    public let output: AnyCodable?
    public let error: String?
}

public struct ACPPlanUpdate: Codable, Sendable {
    public let steps: [ACPPlanStep]?
    public let currentStepIndex: Int?
}

public struct ACPPlanStep: Codable, Sendable, Identifiable {
    public var id: String { stepId ?? UUID().uuidString }
    public let stepId: String?
    public let title: String
    public let description: String?
    public let status: String? // "pending", "in_progress", "completed", "failed"
}

public struct ACPUsageUpdate: Codable, Sendable {
    public let used: Int?
    public let size: Int?
    public let cost: Double?
}
