import Foundation
import Network
import os

actor NodeLink {
	enum Event: Sendable {
		case state(LinkState)
		case status(Wire.NodeInfo)
		case locked(Wire.Lock)
		case password(isSet: Bool)
		case passwordRefused(PasswordOutcome)
		case latency(TimeInterval)
		case pong(Int, Wire.Usage?)
		case usage(Wire.Usage)
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
			var hosts: [String] = []
			
			for host in [preferred, endpoint.host, NodeEndpoint.fallback.host] {
				guard let host, !hosts.contains(host) else { continue }
				hosts.append(host)
			}
			
			let urls = hosts.compactMap { host in
				var target = endpoint
				target.host = host
				return target.url(scheme: "ws", path: "/ws")
			}
			
			continuation.yield(.state(.connecting))
			let reachedNode = await run(urls)
			if Task.isCancelled { return }
			
			failures = reachedNode ? 0 : failures + 1
			for remaining in stride(from: min(3, max(1, failures)), to: 0, by: -1) {
				if Task.isCancelled { return }
				continuation.yield(.state(.retrying(seconds: remaining)))
				try? await Task.sleep(for: .seconds(1))
			}
		}
	}
	
	private func run(_ urls: [URL]) async -> Bool {
		guard let link = await first(of: urls.map { NWConnection(to: .url($0), using: Self.parameters()) }), !Task.isCancelled else { return false }
		connection = link
		await send(Wire.Command.hello.message)
		startHeartbeat()
		
		var reached = false
		var state = LinkState.connecting
		while !Task.isCancelled, let message = await message(from: link) {
			reached = true
			let event = Wire.event(message)
			var arrived = state
			
			switch event {
			case .locked: arrived = .locked
			case .some: arrived = .connected
			case nil: break
			}
			
			if arrived != state {
				state = arrived
				continuation.yield(.state(arrived))
			}
			
			receive(event)
		}
		
		if connection === link { close() }
		return reached
	}
	
	private static func parameters() -> NWParameters {
		let parameters = NWParameters.tcp
		let websocket = NWProtocolWebSocket.Options()
		websocket.autoReplyPing = true
		parameters.defaultProtocolStack.applicationProtocols.insert(websocket, at: 0)
		
		if let tcp = parameters.defaultProtocolStack.transportProtocol as? NWProtocolTCP.Options {
			tcp.noDelay = true
			tcp.connectionTimeout = 5
		}
		
		return parameters
	}
	
	private func first(of links: [NWConnection]) async -> NWConnection? {
		let race = OSAllocatedUnfairLock(initialState: (isOver: false, failed: Set<ObjectIdentifier>()))
		
		return await withTaskCancellationHandler {
			await withCheckedContinuation { (done: CheckedContinuation<NWConnection?, Never>) in
				for link in links {
					link.stateUpdateHandler = { state in
						let isReady: Bool
						
						switch state {
						case .ready: isReady = true
						case .failed, .cancelled, .waiting: isReady = false
						default: return
						}
						
						let winner: NWConnection?? = race.withLock { race in
							guard !race.isOver else { return nil }
							
							if isReady {
								race.isOver = true
								return .some(link)
							}
							
							race.failed.insert(ObjectIdentifier(link))
							guard race.failed.count == links.count else { return nil }
							race.isOver = true
							return .some(nil)
						}
						
						guard let winner else { return }
						
						for other in links where other !== winner {
							other.cancel()
						}
						
						done.resume(returning: winner)
					}
					
					link.start(queue: queue)
				}
				
				queue.asyncAfter(deadline: .now() + 5) {
					guard !race.withLock({ $0.isOver }) else { return }
					
					for link in links {
						link.cancel()
					}
				}
			}
		} onCancel: {
			for link in links {
				link.cancel()
			}
		}
	}
	
	private func message(from link: NWConnection) async -> URLSessionWebSocketTask.Message? {
		await withCheckedContinuation { (done: CheckedContinuation<URLSessionWebSocketTask.Message?, Never>) in
			link.receiveMessage { content, context, _, error in
				let metadata = context?.protocolMetadata(definition: NWProtocolWebSocket.definition) as? NWProtocolWebSocket.Metadata
				
				guard error == nil, let metadata, metadata.opcode != .close else {
					done.resume(returning: nil)
					return
				}
				
				if metadata.opcode == .text {
					done.resume(returning: .string(String(decoding: content ?? Data(), as: UTF8.self)))
				} else {
					done.resume(returning: .data(content ?? Data()))
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
	
	private func receive(_ event: Event?) {
		lastHeard = Date()
		guard let event else { return }
		
		guard case let .pong(seq, usage) = event else {
			continuation.yield(event)
			return
		}
		
		if let usage {
			continuation.yield(.usage(usage))
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
