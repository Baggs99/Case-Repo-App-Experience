/*
 * Purpose: WebSocket client for the practice-session signaling channel
 *          (GET /ws/practice/{session_id}) — connect, send, receive,
 *          heartbeat, and a single automatic reconnect on unexpected drop.
 * Inputs: API_BASE_URL (Bundle Info.plist); session cookie in
 *         HTTPCookieStorage.shared (set by APIClient's login flow).
 * Outputs: none (network side effects only); inbound messages are surfaced
 *          via an AsyncStream<SignalMessage>.
 * Run: let client = SignalingClient(); for await msg in client.connect(sessionId: id) { ... }
 */

import Foundation

@MainActor
final class SignalingClient {
    private var task: URLSessionWebSocketTask?
    private var session: URLSession?
    private var continuation: AsyncStream<SignalMessage>.Continuation?
    private var sessionId: Int?
    private var heartbeatTask: Task<Void, Never>?
    private var receiveLoopTask: Task<Void, Never>?
    private var didReconnect = false
    private var isDisconnecting = false

    private let heartbeatInterval: TimeInterval

    init(heartbeatInterval: TimeInterval = 20) {
        self.heartbeatInterval = heartbeatInterval
    }

    /// Connects to the signaling socket for `sessionId` and returns a stream
    /// of decoded inbound messages. Malformed frames are dropped silently
    /// (SignalMessage.parse returning nil), never surfaced as a message.
    func connect(sessionId: Int) -> AsyncStream<SignalMessage> {
        self.sessionId = sessionId
        self.didReconnect = false
        self.isDisconnecting = false

        return AsyncStream { continuation in
            self.continuation = continuation
            self.openSocket(sessionId: sessionId)
            continuation.onTermination = { [weak self] _ in
                Task { @MainActor in
                    self?.teardown()
                }
            }
        }
    }

    /// Sends a pre-encoded outbound frame (from SignalMessage's outbound
    /// helpers). Never call this with sdp/ice payloads — those are P3 media
    /// concerns and out of scope for this client.
    func send(_ data: Data) {
        task?.send(.data(data)) { _ in }
    }

    func disconnect() {
        isDisconnecting = true
        task?.cancel(with: .normalClosure, reason: nil)
        teardown()
        continuation?.finish()
    }

    // MARK: - Socket lifecycle

    private func openSocket(sessionId: Int) {
        guard let url = Self.webSocketURL(sessionId: sessionId) else {
            continuation?.finish()
            return
        }

        let configuration = URLSessionConfiguration.default
        configuration.httpCookieStorage = HTTPCookieStorage.shared
        let session = URLSession(configuration: configuration)
        let task = session.webSocketTask(with: url)

        self.session = session
        self.task = task

        task.resume()
        startReceiveLoop()
        startHeartbeat()
    }

    private func startReceiveLoop() {
        receiveLoopTask?.cancel()
        receiveLoopTask = Task { [weak self] in
            await self?.receiveNext()
        }
    }

    private func receiveNext() async {
        guard let task else { return }
        do {
            let message = try await task.receive()
            guard !Task.isCancelled else { return }
            switch message {
            case .data(let data):
                if let parsed = SignalMessage.parse(data) {
                    continuation?.yield(parsed)
                }
            case .string(let text):
                if let parsed = SignalMessage.parse(Data(text.utf8)) {
                    continuation?.yield(parsed)
                }
            @unknown default:
                break
            }
            startReceiveLoop()
        } catch {
            handleDrop()
        }
    }

    private func handleDrop() {
        guard !isDisconnecting else { return }
        guard !didReconnect, let sessionId else {
            continuation?.finish()
            teardown()
            return
        }
        // One automatic reconnect on an unexpected drop.
        didReconnect = true
        heartbeatTask?.cancel()
        task?.cancel()
        openSocket(sessionId: sessionId)
    }

    private func teardown() {
        heartbeatTask?.cancel()
        heartbeatTask = nil
        receiveLoopTask?.cancel()
        receiveLoopTask = nil
        task = nil
        session = nil
    }

    // MARK: - Heartbeat

    private func startHeartbeat() {
        heartbeatTask?.cancel()
        heartbeatTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: UInt64(self.heartbeatInterval * 1_000_000_000))
                guard !Task.isCancelled else { return }
                self.send(SignalMessage.ping())
            }
        }
    }

    // MARK: - URL derivation

    static func webSocketURL(sessionId: Int) -> URL? {
        let base: URL
        if let configured = Bundle.main.object(forInfoDictionaryKey: "API_BASE_URL") as? String,
           let url = URL(string: configured) {
            base = url
        } else {
            base = URL(string: "http://127.0.0.1:8077")!
        }

        guard var components = URLComponents(url: base, resolvingAgainstBaseURL: false) else {
            return nil
        }
        switch components.scheme {
        case "http": components.scheme = "ws"
        case "https": components.scheme = "wss"
        default: break
        }
        components.path = "/ws/practice/\(sessionId)"
        return components.url
    }
}
