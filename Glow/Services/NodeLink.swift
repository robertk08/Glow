import Foundation

enum LinkState: Sendable, Equatable {
	case offline
	case connecting
	case connected
	case retrying(seconds: Int)
	
	var isConnected: Bool { self == .connected }
	
	var name: String {
		switch self {
		case .offline: "Not connected"
		case .connecting: "Connecting"
		case .connected: "Connected"
		case let .retrying(seconds): "Reconnecting in \(seconds)s"
		}
	}
	
	func summary(latency: TimeInterval?) -> String {
		guard self == .connected, let latency else { return name }
		return "Connected · \(Int(latency * 1000)) ms"
	}
}

enum LinkEvent: Sendable {
	case state(LinkState)
	case status(Wire.NodeInfo)
	case latency(TimeInterval)
}

actor NodeLink {
	nonisolated let events: AsyncStream<LinkEvent>
	
	private let continuation: AsyncStream<LinkEvent>.Continuation
	private var socket: URLSessionWebSocketTask?
	private var supervisor: Task<Void, Never>?
	private var heartbeat: Task<Void, Never>?
	private var pings: [Int: Date] = [:]
	private var seq = 0
	
	private let session: URLSession = {
		let configuration = URLSessionConfiguration.ephemeral
		configuration.waitsForConnectivity = false
		configuration.timeoutIntervalForRequest = 8
		return URLSession(configuration: configuration)
	}()
	
	init() {
		let (stream, continuation) = AsyncStream<LinkEvent>.makeStream(bufferingPolicy: .bufferingNewest(64))
		events = stream
		self.continuation = continuation
	}
	
	func connect(to endpoint: NodeEndpoint) {
		supervisor?.cancel()
		supervisor = Task { [weak self] in
			await self?.supervise(endpoint)
		}
	}
	
	func send(start: DMXAddress, values: [UInt8]) {
		socket?.send(.data(Wire.frame(start: start, values: values))) { _ in }
	}
	
	func send(_ command: Wire.Command) {
		guard let json = command.json else { return }
		socket?.send(.string(json)) { _ in }
	}
	
	private func supervise(_ endpoint: NodeEndpoint) async {
		var attempt = 0
		while !Task.isCancelled {
			guard let url = endpoint.socketURL else { return }
			
			continuation.yield(.state(.connecting))
			let reachedNode = await run(url)
			if Task.isCancelled { return }
			
			attempt = reachedNode ? 1 : attempt + 1
			for remaining in stride(from: min(15, 1 << (attempt - 1)), to: 0, by: -1) {
				if Task.isCancelled { return }
				continuation.yield(.state(.retrying(seconds: remaining)))
				try? await Task.sleep(for: .seconds(1))
			}
		}
	}
	
	private func run(_ url: URL) async -> Bool {
		let task = session.webSocketTask(with: url)
		socket = task
		task.resume()
		
		send(.hello)
		startHeartbeat()
		
		var reached = false
		while !Task.isCancelled {
			do {
				let message = try await task.receive()
				if !reached {
					reached = true
					continuation.yield(.state(.connected))
				}
				receive(message)
			} catch {
				break
			}
		}
		
		close()
		return reached
	}
	
	private func close() {
		heartbeat?.cancel()
		heartbeat = nil
		socket?.cancel(with: .goingAway, reason: nil)
		socket = nil
		pings.removeAll()
	}
	
	private func receive(_ message: URLSessionWebSocketTask.Message) {
		let data: Data? = switch message {
		case let .string(text): text.data(using: .utf8)
		case let .data(data): data
		@unknown default: nil
		}
		
		guard let data, let reply = Wire.Reply.decode(data) else { return }
		
		switch reply {
		case let .status(info):
			continuation.yield(.status(info))
		case let .pong(seq):
			if let sent = pings.removeValue(forKey: seq) {
				continuation.yield(.latency(Date().timeIntervalSince(sent)))
			}
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
		seq += 1
		pings[seq] = Date()
		pings = pings.filter { Date().timeIntervalSince($0.value) < 10 }
		send(.ping(seq: seq))
	}
}
