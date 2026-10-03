import Foundation

/// Unified transport interface for communicating with an ACP agent.
public protocol ACPTransport: AnyObject, Sendable {
    /// Starts the transport (launches subprocess, opens WebSocket, etc.)
    func start() async throws

    /// Sends raw JSON-RPC bytes (NDJSON / WebSocket frame)
    func send(data: Data) async throws

    /// Asynchronous stream of incoming raw bytes (per line or per message)
    func messageStream() -> AsyncStream<Data>

    /// Asynchronous stream of stderr log lines (for telemetry / debugging)
    func stderrStream() -> AsyncStream<String>

    /// Stops and tears down the transport
    func stop() async

    /// Whether the transport is actively running and ready to transmit
    var isRunning: Bool { get }
}
