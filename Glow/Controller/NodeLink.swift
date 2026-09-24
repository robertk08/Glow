import Foundation
import Network
import os

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
	private var connection: NWConnection?
	private var supervisor: Task<Void, Never>?
	private var heartbeat: Task<Void, Never>?
	private var lastHeard = Date()
	private var preferred: String?
	private var pings: [Int: Date] = [:]
	private var seq = 0
	
	private let queue = DispatchQueue(label: "glow.link")
	
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
		guard let connection else { return }
		var content = Data()
		var opcode = NWProtocolWebSocket.Opcode.binary
		
		switch message {
		case let .data(data):
			content = data
		case let .string(text):
			content = Data(text.utf8)
			opcode = .text
		@unknown default:
			return
		}
		
		let context = NWConnection.ContentContext(identifier: "message", metadata: [NWProtocolWebSocket.Metadata(opcode: opcode)])
		
		await withCheckedContinuation { (done: CheckedContinuation<Void, Never>) in
			connection.send(content: content, contentContext: context, isComplete: true, completion: .contentProcessed { _ in done.resume() })
		}
	}
	
	private func supervise(_ endpoint: NodeEndpoint) async {
		var failures = 0
		while !Task.isCancelled {
			var target = endpoint
			
			if let preferred {
				target.host = preferred
			} else if failures % 2 == 1 {
				target.host = NodeEndpoint.fallback.host
			}
			
			guard let url = target.url(scheme: "ws", path: "/ws") else { return }
			
			continuation.yield(.state(.connecting))
			let reachedNode = await run(url)
			if Task.isCancelled { return }
			
			if reachedNode {
				failures = 0
			} else {
				preferred = nil
				failures += 1
			}
			for remaining in stride(from: min(3, max(1, failures)), to: 0, by: -1) {
				if Task.isCancelled { return }
				continuation.yield(.state(.retrying(seconds: remaining)))
				try? await Task.sleep(for: .seconds(1))
			}
		}
	}
	
	private func run(_ url: URL) async -> Bool {
		let parameters = NWParameters.tcp
		let websocket = NWProtocolWebSocket.Options()
		websocket.autoReplyPing = true
		parameters.defaultProtocolStack.applicationProtocols.insert(websocket, at: 0)
		
		if let tcp = parameters.defaultProtocolStack.transportProtocol as? NWProtocolTCP.Options {
			tcp.noDelay = true
			tcp.connectionTimeout = 5
		}
		
		let link = NWConnection(to: .url(url), using: parameters)
		connection = link
		guard await opened(link) else {
			if connection === link { close() }
			return false
		}
		
		await send(Wire.Command.hello.message)
		startHeartbeat()
		
		var reached = false
		while !Task.isCancelled, let message = await message(from: link) {
			if !reached {
				reached = true
				continuation.yield(.state(.connected))
			}
			receive(message)
		}
		
		if connection === link { close() }
		return reached
	}
	
	private func opened(_ link: NWConnection) async -> Bool {
		let answered = OSAllocatedUnfairLock(initialState: false)
		
		return await withCheckedContinuation { (done: CheckedContinuation<Bool, Never>) in
			link.stateUpdateHandler = { state in
				var outcome: Bool?
				
				switch state {
				case .ready: outcome = true
				case .failed, .cancelled, .waiting: outcome = false
				default: break
				}
				
				guard let outcome, answered.withLock({ wasAnswered in
					defer { wasAnswered = true }
					return !wasAnswered
				}) else { return }
				done.resume(returning: outcome)
			}
			
			link.start(queue: queue)
			
			queue.asyncAfter(deadline: .now() + 5) {
				guard !answered.withLock({ $0 }) else { return }
				link.cancel()
			}
		}
	}
	
	private func message(from link: NWConnection) async -> URLSessionWebSocketTask.Message? {
		await withCheckedContinuation { (done: CheckedContinuation<URLSessionWebSocketTask.Message?, Never>) in
			link.receiveMessage { content, context, _, error in
				let metadata = context?.protocolMetadata(definition: NWProtocolWebSocket.definition) as? NWProtocolWebSocket.Metadata
				
				guard error == nil, let content, let metadata, metadata.opcode != .close else {
					done.resume(returning: nil)
					return
				}
				
				if metadata.opcode == .text {
					done.resume(returning: .string(String(decoding: content, as: UTF8.self)))
				} else {
					done.resume(returning: .data(content))
				}
			}
		}
	}
	
	private func close() {
		heartbeat?.cancel()
		heartbeat = nil
		connection?.cancel()
		connection = nil
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
			connection?.cancel()
			return
		}
		
		seq += 1
		pings[seq] = Date()
		pings = pings.filter { Date().timeIntervalSince($0.value) < 10 }
		await send(Wire.Command.ping(seq: seq).message)
	}
}
