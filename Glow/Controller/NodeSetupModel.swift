import NetworkExtension
import Observation
import SwiftUI

@Observable @MainActor
final class NodeSetupModel {
	var step = NodeSetupStep.findController
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
	
	private let setup = NodeSetup()
	
	func waitForController(console: Console) async {
		failure = nil
		
		if console.link.isConnected {
			expectedNodeID = console.endpoint.nodeID
			do {
				try await NodeSetup(host: console.endpoint.host, port: console.endpoint.port).begin()
			} catch {
				failure = "Could not open controller setup. Check the connection and update the controller firmware if needed."
				return
			}
		}
		
		let configuration = NEHotspotConfiguration(ssid: "Glow Setup")
		configuration.joinOnce = true
		
		do {
			try await NEHotspotConfigurationManager.shared.apply(configuration)
		} catch {
			let error = error as NSError
			if error.domain != NEHotspotConfigurationErrorDomain || error.code != NEHotspotConfigurationError.alreadyAssociated.rawValue {
				failure = "Could not join Glow Setup. Check that the controller is powered on, then try again. You can also join Glow Setup in the Settings app."
				return
			}
		}
		
		for _ in 0..<15 {
			guard !Task.isCancelled else { return }
			if let info = try? await setup.info() {
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
			
			guard let found = try? await setup.scan(), !found.isEmpty else { continue }
			
			networks = found
			return
		}
		
		failure = "The controller never sent back a list of networks. Check that your iPhone is still on Glow Setup and try again."
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
		var provisioned: NodeEndpoint?
		
		for _ in 0..<40 {
			guard !Task.isCancelled else { return }
			try? await Task.sleep(for: .seconds(2))
			
			if provisioned == nil, let info = try? await setup.info(), info.id == nodeID {
				if info.didRefuse {
					failure = "The controller could not join \(ssid). Check the network and credentials."
					step = .password
					return
				}
				
				if info.hasJoined(ssid: ssid), !info.ip.isEmpty, info.ip != setup.host {
					provisioned = NodeEndpoint(host: info.ip, name: info.name, nodeID: info.id)
					NEHotspotConfigurationManager.shared.removeConfiguration(forSSID: "Glow Setup")
					
					if selected?.enterprise != true {
						let configuration: NEHotspotConfiguration
						if selected?.secure == true {
							configuration = NEHotspotConfiguration(ssid: ssid, passphrase: password, isWEP: false)
						} else {
							configuration = NEHotspotConfiguration(ssid: ssid)
						}
						
						do {
							try await NEHotspotConfigurationManager.shared.apply(configuration)
						} catch {
							let error = error as NSError
							if error.domain != NEHotspotConfigurationErrorDomain || error.code != NEHotspotConfigurationError.alreadyAssociated.rawValue {
								failure = "The controller joined \(ssid). Join that network in Settings to control it."
							}
						}
					}
					
					user = ""
					password = ""
					continue
				}
			}
			
			guard let found = provisioned ?? discovery.endpoints.first(where: { $0.nodeID == nodeID }), let info = try? await NodeSetup(host: found.host, port: found.port).info(), info.id == nodeID, info.hasJoined(ssid: ssid) else { continue }
			
			user = ""
			password = ""
			console.endpoint = found
			failure = nil
			step = .done
			return
		}
		
		failure = "Glow lost sight of the controller. Put your iPhone back on \(ssid), then pick the controller in Settings."
	}
}
