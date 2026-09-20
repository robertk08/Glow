import Foundation

actor NodeLink {
	enum Event: Sendable {
		case state(LinkState)
		case status(Wire.NodeInfo)
		case latency(TimeInterval)
		case frame(start: DMXAddress, values: [UInt8])
		case master(Double)
		case blackout(Bool)
		case scene(String)
		case notice(Wire.Notice)
	}
	
	nonisolated let events: AsyncStream<Event>
	
	private let continuation: AsyncStream<Event>.Continuation
	private static let silenceLimit: TimeInterval = 5
	private var socket: URLSessionWebSocketTask?
	private var supervisor: Task<Void, Never>?
	private var heartbeat: Task<Void, Never>?
	private var lastHeard = Date()
	private var preferred: String?
	private var pings: [Int: Date] = [:]
	private var seq = 0
	
	private let session: URLSession = {
		let configuration = URLSessionConfiguration.ephemeral
		configuration.waitsForConnectivity = false
		configuration.timeoutIntervalForRequest = 8
		return URLSession(configuration: configuration)
	}()
	
	init() {
		let (stream, continuation) = AsyncStream<Event>.makeStream(bufferingPolicy: .bufferingNewest(64))
		events = stream
		self.continuation = continuation
	}
	
	func connect(to endpoint: NodeEndpoint) {
		supervisor?.cancel()
		close()
		supervisor = Task { [weak self] in
			await self?.supervise(endpoint)
		}
	}
	
	func send(_ opcode: UInt8, start: DMXAddress, values: [UInt8]) async {
		guard let socket else { return }
		
		try? await socket.send(.data(Wire.frame(opcode, start: start, values: values)))
	}
	
	func prefer(_ host: String?) {
		preferred = host
	}
	
	func send(_ frame: Data) async {
		guard let socket else { return }
		
		try? await socket.send(.data(frame))
	}
	
	func send(_ command: Wire.Command) async {
		guard let socket, let json = command.json else { return }
		
		try? await socket.send(.string(json))
	}
	
	private func supervise(_ endpoint: NodeEndpoint) async {
		var attempt = 0
		while !Task.isCancelled {
			var target = endpoint
			
			if let preferred {
				target = NodeEndpoint(host: preferred, port: endpoint.port, name: endpoint.name, nodeID: endpoint.nodeID)
			}
			
			guard let url = target.socketURL else { return }
			
			continuation.yield(.state(.connecting))
			let reachedNode = await run(url)
			if Task.isCancelled { return }
			
			if reachedNode {
				attempt = 1
			} else {
				preferred = nil
				attempt = min(attempt + 1, 5)
			}
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
		
		await send(.hello)
		startHeartbeat()
		
		var reached = false
		while !Task.isCancelled {
			do {
				let message = try await task.receive()
				guard !Task.isCancelled else { break }
				if !reached {
					reached = true
					continuation.yield(.state(.connected))
				}
				receive(message)
			} catch {
				break
			}
		}
		
		if socket === task { close() }
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
		lastHeard = Date()

		if case let .data(data) = message {
			if data.first == Wire.documentOpcode {
				guard let notice = Wire.decode(document: data) else { return }
				continuation.yield(.notice(notice))
				return
			}
			
			guard let frame = Wire.decode(frame: data) else { return }
			continuation.yield(.frame(start: frame.start, values: frame.values))
			return
		}
		
		guard case let .string(text) = message, let data = text.data(using: .utf8) else { return }
		guard let reply = Wire.Reply.decode(data) else { return }
		
		switch reply {
		case let .status(info):
			continuation.yield(.status(info))
		case let .pong(seq):
			if let sent = pings.removeValue(forKey: seq) {
				continuation.yield(.latency(Date().timeIntervalSince(sent)))
			}
		case let .master(level):
			continuation.yield(.master(level))
		case let .blackout(on):
			continuation.yield(.blackout(on))
		case let .scene(identifier):
			continuation.yield(.scene(identifier))
		case let .notice(notice):
			continuation.yield(.notice(notice))
		}
	}
	
	private func startHeartbeat() {
		heartbeat?.cancel()
		lastHeard = Date()
		heartbeat = Task { [weak self] in
			while !Task.isCancelled {
				try? await Task.sleep(for: .seconds(2))
				guard !Task.isCancelled else { return }
				await self?.ping()
			}
		}
	}
	
	private func ping() async {
		guard Date().timeIntervalSince(lastHeard) < Self.silenceLimit else {
			socket?.cancel(with: .goingAway, reason: nil)
			return
		}
		
		seq += 1
		pings[seq] = Date()
		pings = pings.filter { Date().timeIntervalSince($0.value) < 10 }
		await send(.ping(seq: seq))
	}
}
