import Foundation

/// WebSocket-based transport for communicating with remote or containerized ACP servers.
public final class ACPWebSocketClient: NSObject, ACPTransport, URLSessionWebSocketDelegate, @unchecked Sendable {
    private let url: URL
    private let lock = NSLock()
    private var webSocketTask: URLSessionWebSocketTask?
    private var session: URLSession?

    private var messageContinuation: AsyncStream<Data>.Continuation?
    private var stderrContinuation: AsyncStream<String>.Continuation?

    private var _isRunning: Bool = false

    public var isRunning: Bool {
        lock.withLock { _isRunning }
    }

    public init(url: URL) {
        self.url = url
        super.init()
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
        let alreadyRunning = lock.withLock {
            if _isRunning { return true }
            return false
        }
        if alreadyRunning { return }

        let configuration = URLSessionConfiguration.default
        let newSession = URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
        let task = newSession.webSocketTask(with: url)

        lock.withLock {
            self.session = newSession
            self.webSocketTask = task
            self._isRunning = true
        }

        task.resume()
        startReceiveLoop(task: task)
    }

    public func send(data: Data) async throws {
        let task: URLSessionWebSocketTask? = lock.withLock {
            guard _isRunning else { return nil }
            return self.webSocketTask
        }

        guard let ws = task else {
            throw NSError(
                domain: "ACPWebSocketClient",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "WebSocket is not connected"]
            )
        }

        if let string = String(data: data, encoding: .utf8) {
            try await ws.send(.string(string))
        } else {
            try await ws.send(.data(data))
        }
    }

    public func stop() async {
        let (task, sess): (URLSessionWebSocketTask?, URLSession?) = lock.withLock {
            guard _isRunning else { return (nil, nil) }
            self._isRunning = false
            return (self.webSocketTask, self.session)
        }

        guard let ws = task else { return }

        ws.cancel(with: .goingAway, reason: nil)
        sess?.invalidateAndCancel()

        lock.withLock {
            messageContinuation?.finish()
            stderrContinuation?.finish()
        }
    }

    // MARK: - Private Receive Loop

    private func startReceiveLoop(task: URLSessionWebSocketTask) {
        Task.detached { [weak self] in
            while let self = self, self.isRunning {
                do {
                    let message = try await task.receive()
                    switch message {
                    case .data(let data):
                        _ = self.lock.withLock {
                            self.messageContinuation?.yield(data)
                        }
                    case .string(let str):
                        if let data = str.data(using: .utf8) {
                            _ = self.lock.withLock {
                                self.messageContinuation?.yield(data)
                            }
                        }
                    @unknown default:
                        break
                    }
                } catch {
                    self.lock.withLock {
                        self._isRunning = false
                        self.messageContinuation?.finish()
                    }
                    break
                }
            }
        }
    }
}
