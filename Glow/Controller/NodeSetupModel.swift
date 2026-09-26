import NetworkExtension
import Observation
import SwiftUI

@Observable @MainActor
final class NodeSetupModel {
	enum Step: Equatable {
		case findController, chooseNetwork, password, joining, done
	}
	
	var step = Step.findController
	var networks: [NodeNetwork] = []
	var selected: NodeNetwork?
	var user = ""
	var password = ""
	var failure: String?
	
	private var nodeID = ""
	private var expectedNodeID: String?
	
	var canJoin: Bool {
		guard selected?.secure == true else { return selected != nil }
		guard !password.isEmpty else { return false }
		return selected?.enterprise != true || !user.isEmpty
	}
	
	private let store = NodeStore()
	
	func waitForController(console: Console) async {
		failure = nil
		
		if console.link.isConnected {
			expectedNodeID = await store.setup(at: console.reachable)?.id
			do {
				try await store.command("setup", at: console.reachable)
			} catch {
				failure = "Could not open controller setup. Check the connection and update the controller firmware if needed."
				return
			}
		}
		
		let configuration = NEHotspotConfiguration(ssid: "Glow Setup")
		configuration.joinOnce = true
		
		guard await join(configuration) else {
			failure = "Could not join Glow Setup. Check that the controller is powered on, then try again. You can also join Glow Setup in the Settings app."
			return
		}
		
		for _ in 0..<15 {
			guard !Task.isCancelled else { return }
			if let info = await store.setup(at: .setup) {
				if let expectedNodeID, info.id != expectedNodeID {
					failure = "Glow Setup belongs to a different controller. Power off other controllers being set up and try again."
					return
				}
				nodeID = info.id
				step = .chooseNetwork
				return
			}
			
			try? await Task.sleep(for: .seconds(2))
		}
		
		failure = "Glow Setup did not respond. Check that the controller is powered on and try again."
	}
	
	func loadNetworks() async {
		failure = nil
		
		for attempt in 0..<15 {
			guard !Task.isCancelled else { return }
			if attempt > 0 {
				try? await Task.sleep(for: .seconds(2))
			}
			
			guard let found = await store.networks(at: .setup), !found.isEmpty else { continue }
			
			networks = found
			return
		}
		
		failure = "The controller never sent back a list of networks. Check that your iPhone is still on Glow Setup and try again."
	}
	
	private func join(_ configuration: NEHotspotConfiguration) async -> Bool {
		do {
			try await NEHotspotConfigurationManager.shared.apply(configuration)
			return true
		} catch {
			let error = error as NSError
			return error.domain == NEHotspotConfigurationErrorDomain && error.code == NEHotspotConfigurationError.alreadyAssociated.rawValue
		}
	}
	
	func choose(network: NodeNetwork) {
		selected = network
		user = ""
		password = ""
		if network.secure {
			step = .password
		} else {
			step = .joining
		}
	}
	
	func join(console: Console) async {
		step = .joining
		failure = nil
		
		guard let ssid = selected?.ssid else { return }
		
		do {
			try await store.command("provision", at: .setup, fields: ["ssid": ssid, "user": user, "password": password])
		} catch {
			failure = error.localizedDescription
			step = .password
			return
		}
		
		var provisioned: NodeEndpoint?
		
		for _ in 0..<40 {
			guard !Task.isCancelled else { return }
			try? await Task.sleep(for: .seconds(2))
			
			if provisioned == nil, let info = await store.setup(at: .setup), info.id == nodeID {
				if info.didRefuse {
					failure = "The controller could not join \(ssid). Check the network and credentials."
					step = .password
					return
				}
				
				if info.hasJoined(ssid: ssid), !info.ip.isEmpty, info.ip != NodeEndpoint.setup.host {
					provisioned = NodeEndpoint(host: info.ip)
					NEHotspotConfigurationManager.shared.removeConfiguration(forSSID: "Glow Setup")
					
					if selected?.enterprise != true {
						let configuration: NEHotspotConfiguration
						if selected?.secure == true {
							configuration = NEHotspotConfiguration(ssid: ssid, passphrase: password, isWEP: false)
						} else {
							configuration = NEHotspotConfiguration(ssid: ssid)
						}
						
						if await !join(configuration) {
							failure = "The controller joined \(ssid). Join that network in Settings to control it."
						}
					}
					
					user = ""
					password = ""
					continue
				}
			}
			
			let found = provisioned ?? .fallback
			guard let info = await store.setup(at: found), info.id == nodeID, info.hasJoined(ssid: ssid) else { continue }
			
			user = ""
			password = ""
			console.endpoint = found
			failure = nil
			step = .done
			return
		}
		
		failure = "Glow lost sight of the controller. Put your iPhone back on \(ssid) and Glow finds it by itself."
	}
}
