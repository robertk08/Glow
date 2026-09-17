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
	
	var canJoin: Bool {
		guard !password.isEmpty else { return false }
		return selected?.enterprise != true || !user.isEmpty
	}
	
	private let setup = NodeSetup()
	
	func waitForController() async {
		while step == .findController, !Task.isCancelled {
			if (try? await setup.info()) != nil {
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
	
	func join(console: Console) async {
		step = .joining
		failure = nil
		
		guard let ssid = selected?.ssid else { return }
		
		do {
			try await setup.join(ssid: ssid, user: user, password: password)
			user = ""
			password = ""
		} catch {
			failure = error.localizedDescription
			return
		}
		
		for _ in 0..<30 {
			try? await Task.sleep(for: .seconds(2))
			
			if let info = try? await NodeSetup(host: console.endpoint.host, port: console.endpoint.port).info(), info.isProvisioned {
				step = .done
				console.connect()
				return
			}
		}
		
		failure = "Couldn't find the controller afterwards. If it could not join, it goes back to making its own Glow Setup network so you can try again."
	}
}
