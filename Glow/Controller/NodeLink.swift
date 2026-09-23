import Foundation

actor NodeLink {
	enum Event: Sendable {
		case state(LinkState)
		case status(Wire.NodeInfo)
		case latency(TimeInterval)
		case pong(Int)
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
		configuration.timeoutIntervalForRequest = 5
		return URLSession(configuration: configuration)
	}()
	
	init() {
		let (stream, continuation) = AsyncStream<Event>.makeStream()
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
	
	func prefer(_ host: String?) {
		preferred = host
	}
	
	func send(_ message: URLSessionWebSocketTask.Message) async {
		guard let socket else { return }
		
		try? await socket.send(message)
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
			for remaining in stride(from: min(3, 1 << (attempt - 1)), to: 0, by: -1) {
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
		
		await send(Wire.Command.hello.message)
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
		guard let event = Wire.event(message) else { return }
		
		guard case let .pong(seq) = event else {
			continuation.yield(event)
			return
		}
		
		guard let sent = pings.removeValue(forKey: seq) else { return }
		continuation.yield(.latency(Date().timeIntervalSince(sent)))
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
		await send(Wire.Command.ping(seq: seq).message)
	}
}
