import Foundation
import Network
import Observation
import os

@Observable @MainActor
final class NodeDiscovery {
	private(set) var endpoints: [NodeEndpoint] = []
	private(set) var isDenied = false
	
	private var browser: NWBrowser?
	
	func start() {
		guard browser == nil else { return }
		
		let browser = NWBrowser(for: .bonjour(type: "_glow._tcp", domain: nil), using: NWParameters())
		
		browser.stateUpdateHandler = { [weak self] state in
			Task { @MainActor in
				guard case let .failed(error) = state else { return }
				self?.isDenied = "\(error)".localizedCaseInsensitiveContains("policy")
			}
		}
		
		browser.browseResultsChangedHandler = { [weak self] results, _ in
			Task { @MainActor in
				await self?.update(results)
			}
		}
		
		self.browser = browser
		browser.start(queue: .main)
	}
	
	func stop() {
		browser?.cancel()
		browser = nil
		endpoints = []
	}
	
	private func update(_ results: Set<NWBrowser.Result>) async {
		var found: [NodeEndpoint] = []
		
		for result in results {
			guard case let .service(name, _, _, _) = result.endpoint,
				  let resolved = await Self.resolve(result.endpoint)
			else { continue }
			
			found.append(NodeEndpoint(host: resolved.host, port: resolved.port, name: name, nodeID: Self.nodeID(result.metadata)))
		}
		
		endpoints = found.sorted { $0.name < $1.name }
	}
	
	private static func nodeID(_ metadata: NWBrowser.Result.Metadata) -> String? {
		guard case let .bonjour(record) = metadata else { return nil }
		return record["id"]
	}
	
	private static func resolve(_ endpoint: NWEndpoint) async -> (host: String, port: Int)? {
		await withCheckedContinuation { continuation in
			let connection = NWConnection(to: endpoint, using: .tcp)
			let resumed = OSAllocatedUnfairLock(initialState: false)
			
			@Sendable func finish(_ value: (host: String, port: Int)?) {
				let shouldResume = resumed.withLock { done in
					guard !done else { return false }
					done = true
					return true
				}
				guard shouldResume else { return }
				connection.cancel()
				continuation.resume(returning: value)
			}
			
			connection.stateUpdateHandler = { state in
				switch state {
				case .ready:
					guard case let .hostPort(host, port) = connection.currentPath?.remoteEndpoint else {
						finish(nil)
						return
					}
					let name = switch host {
					case let .name(name, _): name
					case let .ipv4(address): "\(address)".components(separatedBy: "%").first ?? ""
					case let .ipv6(address): "\(address)".components(separatedBy: "%").first ?? ""
					@unknown default: ""
					}
					finish(name.isEmpty ? nil : (name, Int(port.rawValue)))
				case .failed, .cancelled:
					finish(nil)
				default:
					break
				}
			}
			
			connection.start(queue: .global(qos: .utility))
			
			Task {
				try? await Task.sleep(for: .seconds(4))
				finish(nil)
			}
		}
	}
}
