import Foundation

nonisolated enum ConnectionState: Sendable, Equatable {
    case idle
    case connecting
    case connected
    /// Waiting to retry. Drops are routine here — DHCP renewals, router
    /// reboots, 2.4 GHz interference — so this is an expected state with a
    /// countdown, not an error the user has to acknowledge.
    case waitingToRetry(attempt: Int, seconds: Int)
    case failed(reason: String)

    var isConnected: Bool { self == .connected }
}

nonisolated enum LinkEvent: Sendable {
    case state(ConnectionState)
    case status(Wire.NodeStatus)
    case roundTrip(TimeInterval)
    case nodeError(code: String, message: String)
}

/// Where a node lives, and how we came to know about it.
nonisolated struct ControllerEndpoint: Sendable, Hashable, Codable, Identifiable {
    nonisolated enum Source: String, Sendable, Codable {
        case discovered, manual, fallback
    }

    var host: String
    var port: Int = 80
    var displayName: String
    var source: Source = .manual

    /// The node's own identifier from its Bonjour TXT record, where one was
    /// advertised. Stable across address changes, unlike the host.
    var nodeID: String?

    var id: String { "\(host):\(port)" }

    var webSocketURL: URL? {
        var components = URLComponents()
        components.scheme = "ws"
        components.host = host
        components.port = port == 80 ? nil : port
        components.path = "/ws"
        return components.url
    }

    /// Where the node is before anything has been configured. The firmware
    /// registers this hostname over mDNS, so a stock setup connects with no
    /// input from the user at all.
    static let defaultNode = ControllerEndpoint(
        host: "glow.local",
        displayName: "glow.local",
        source: .fallback
    )
}

/// Owns the socket to the node: connects, keeps connecting, and gets DMX out.
///
/// An actor rather than a main-actor object because the receive loop and the
/// heartbeat both run continuously and neither has any business competing with
/// the UI for the main thread while someone is dragging a fader.
actor ControllerLink {
    private var socket: URLSessionWebSocketTask?
    private var supervisor: Task<Void, Never>?
    private var heartbeat: Task<Void, Never>?
    private var pingSeq = 0
    private var pendingPings: [Int: Date] = [:]
    private let continuation: AsyncStream<LinkEvent>.Continuation

    /// Events for the UI to observe. Replays nothing: the store holds state.
    nonisolated let events: AsyncStream<LinkEvent>

    private let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.waitsForConnectivity = false
        configuration.timeoutIntervalForRequest = 8
        return URLSession(configuration: configuration)
    }()

    init() {
        let (stream, continuation) = AsyncStream<LinkEvent>.makeStream(
            bufferingPolicy: .bufferingNewest(64)
        )
        events = stream
        self.continuation = continuation
    }

    // MARK: - Lifecycle

    func connect(to endpoint: ControllerEndpoint) {
        supervisor?.cancel()
        supervisor = Task { [weak self] in
            await self?.supervise(endpoint)
        }
    }

    func disconnect() {
        supervisor?.cancel()
        supervisor = nil
        teardownSocket()
        emit(.state(.idle))
    }

    /// Reconnect immediately instead of waiting out the current backoff.
    func retryNow(_ endpoint: ControllerEndpoint) {
        connect(to: endpoint)
    }

    private func supervise(_ endpoint: ControllerEndpoint) async {
        var attempt = 0
        while !Task.isCancelled {
            guard let url = endpoint.webSocketURL else {
                emit(.state(.failed(reason: "That address can't be turned into a URL.")))
                return
            }

            emit(.state(.connecting))
            let completed = await runSession(url: url)

            if Task.isCancelled { return }

            // A session that carried at least one message was a real
            // connection, so backoff starts over rather than compounding
            // across an evening of ordinary WiFi hiccups.
            attempt = completed ? 1 : attempt + 1
            let delay = Self.backoffSeconds(attempt: attempt)

            for remaining in stride(from: delay, to: 0, by: -1) {
                if Task.isCancelled { return }
                emit(.state(.waitingToRetry(attempt: attempt, seconds: remaining)))
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    /// Runs one connection to completion. Returns true if it ever reached the
    /// connected state.
    private func runSession(url: URL) async -> Bool {
        let task = session.webSocketTask(with: url)
        socket = task
        task.resume()

        send(.hello(client: "Glow iOS", version: Wire.version))
        startHeartbeat()

        var everConnected = false

        while !Task.isCancelled {
            do {
                let message = try await task.receive()
                if !everConnected {
                    everConnected = true
                    emit(.state(.connected))
                }
                handle(message)
            } catch {
                break
            }
        }

        teardownSocket()
        return everConnected
    }

    private func teardownSocket() {
        heartbeat?.cancel()
        heartbeat = nil
        socket?.cancel(with: .goingAway, reason: nil)
        socket = nil
        pendingPings.removeAll()
    }

    private static func backoffSeconds(attempt: Int) -> Int {
        // 1, 2, 4, 8, capped at 15. Long enough not to hammer a rebooting
        // router, short enough that nobody reaches for the app to fix it.
        min(15, Int(pow(2.0, Double(max(0, attempt - 1)))))
    }

    // MARK: - Sending

    /// Fire-and-forget. A dropped frame is not worth surfacing: the send loop
    /// re-sends the current look on the next tick anyway.
    func send(_ frame: Wire.DMXFrame) {
        guard let socket else { return }
        socket.send(.data(frame.data)) { _ in }
    }

    func send(_ message: Wire.ClientMessage) {
        guard let socket, let data = message.jsonData,
              let text = String(data: data, encoding: .utf8) else { return }
        socket.send(.string(text)) { _ in }
    }

    // MARK: - Receiving

    private func handle(_ message: URLSessionWebSocketTask.Message) {
        let data: Data? = switch message {
        case let .string(text): text.data(using: .utf8)
        case let .data(data): data
        @unknown default: nil
        }

        guard let data, let decoded = Wire.NodeMessage.decode(data) else { return }

        switch decoded {
        case let .status(status):
            emit(.status(status))
        case let .pong(seq):
            if let sent = pendingPings.removeValue(forKey: seq) {
                emit(.roundTrip(Date().timeIntervalSince(sent)))
            }
        case let .error(code, message):
            emit(.nodeError(code: code, message: message))
        }
    }

    private func startHeartbeat() {
        heartbeat?.cancel()
        heartbeat = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(3))
                guard !Task.isCancelled else { return }
                await self?.ping()
            }
        }
    }

    private func ping() {
        pingSeq += 1
        let seq = pingSeq
        pendingPings[seq] = Date()
        // Anything older than a few seconds is never coming back.
        pendingPings = pendingPings.filter { Date().timeIntervalSince($0.value) < 10 }
        send(.ping(seq: seq))
    }

    private func emit(_ event: LinkEvent) {
        continuation.yield(event)
    }
}
