import Observation
import SwiftUI

@Observable @MainActor
final class NodeSetupModel {
	enum Step {
		case findController, chooseNetwork, password, joining, done
	}
	
	var step = Step.findController
	var networks: [NodeSetup.Network] = []
	var selected: NodeSetup.Network?
	var user = ""
	var password = ""
	var failure: String?
	
	private var nodeID = ""
	
	var canJoin: Bool {
		guard !password.isEmpty else { return false }
		return selected?.enterprise != true || !user.isEmpty
	}
	
	private let setup = NodeSetup()
	
	func waitForController() async {
		while step == .findController, !Task.isCancelled {
			if let info = try? await setup.info() {
				nodeID = info.id
				step = .chooseNetwork
				return
			}
			
			try? await Task.sleep(for: .seconds(2))
		}
	}
	
	func loadNetworks() async {
		failure = nil
		
		for attempt in 0..<15 {
			if attempt > 0 {
				try? await Task.sleep(for: .seconds(2))
			}
			
			guard let found = try? await setup.scan(), !found.isEmpty else { continue }
			
			networks = found
			return
		}
		
		failure = "The controller never sent back a list of networks. Check that your iPhone is still on Glow Setup and try again."
	}
	
	func choose(network: NodeSetup.Network) {
		selected = network
		user = ""
		password = ""
		step = network.secure ? .password : .joining
	}
	
	func join(console: Console, discovery: NodeDiscovery) async {
		step = .joining
		failure = nil
		
		guard let ssid = selected?.ssid else { return }
		
		do {
			try await setup.join(ssid: ssid, user: user, password: password)
		} catch {
			failure = error.localizedDescription
			step = .password
			return
		}
		
		discovery.start()
		
		for _ in 0..<40 {
			try? await Task.sleep(for: .seconds(2))
			
			if let info = try? await setup.info() {
				if info.didRefuse {
					failure = "\(ssid) turned that password down."
					step = .password
					return
				}
				
				if info.isProvisioned, !info.ip.isEmpty {
					user = ""
					password = ""
					console.endpoint = NodeEndpoint(host: info.ip, name: info.name, nodeID: info.id)
					step = .done
					return
				}
			}
			
			guard let found = discovery.endpoints.first(where: { $0.nodeID == nodeID }) ?? discovery.endpoints.first else { continue }
			
			user = ""
			password = ""
			console.endpoint = found
			step = .done
			return
		}
		
		failure = "Glow lost sight of the controller. Put your iPhone back on \(ssid), then pick the controller in Settings."
	}
}
