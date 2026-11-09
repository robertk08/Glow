import NetworkExtension
import SwiftUI

enum ControllerWiFi {
	static let name = "Glow Controller"
	
	static func use(console: Console) async -> String? {
		let store = NodeStore()
		let isTold = console.link.isConnected && console.node?.isOwn != true
		
		if isTold {
			do {
				try await store.command("own", at: console.reachable)
			} catch {
				return "The controller did not switch. Check the connection and update the controller firmware if needed."
			}
		}
		
		guard await join(NEHotspotConfiguration(ssid: name)) else {
			return "Could not join \(name). Check that the controller is powered on, then try again. You can also join \(name) in the Settings app."
		}
		
		if !isTold, await !tell(store) {
			return "\(name) did not respond. Check that the controller is powered on and try again."
		}
		
		console.endpoint = .setup
		return nil
	}
	
	static func rejoin(_ ssid: String, console: Console) async -> String? {
		let store = NodeStore()
		
		do {
			try await store.command("rejoin", at: console.reachable, fields: ["ssid": ssid])
		} catch {
			return "The controller did not switch. Check the connection and try again."
		}
		
		for _ in 0..<15 {
			try? await Task.sleep(for: .seconds(2))
			guard let info = await store.setup(at: .setup) else { continue }
			if info.didRefuse { return "The controller could not reach \(ssid), so it keeps running \(name)." }
			guard info.hasJoined(ssid: ssid), !info.ip.isEmpty, info.ip != NodeEndpoint.setup.host else { continue }
			
			NEHotspotConfigurationManager.shared.removeConfiguration(forSSID: name)
			console.endpoint = NodeEndpoint(host: info.ip)
			return nil
		}
		
		return "\(name) did not respond. Check that the controller is powered on and try again."
	}
	
	private static func tell(_ store: NodeStore) async -> Bool {
		for attempt in 0..<10 {
			if attempt > 0 {
				try? await Task.sleep(for: .seconds(2))
			}
			
			if (try? await store.command("own", at: .setup)) != nil { return true }
		}
		
		return false
	}
	
	static func join(_ configuration: NEHotspotConfiguration) async -> Bool {
		do {
			try await NEHotspotConfigurationManager.shared.apply(configuration)
			return true
		} catch {
			let error = error as NSError
			return error.domain == NEHotspotConfigurationErrorDomain && error.code == NEHotspotConfigurationError.alreadyAssociated.rawValue
		}
	}
}

struct UseWiFiButton: View {
	@Environment(Console.self) private var console
	
	var ssid: String?
	let asks: Bool
	
	@State private var isAsking = false
	@State private var isWorking = false
	@State private var failure: String?
	
	var body: some View {
		Button {
			if asks {
				isAsking = true
			} else {
				use()
			}
		} label: {
			Label {
				Text(title)
			} icon: {
				if isWorking {
					ProgressView()
				} else {
					Image(systemName: ssid == nil ? "antenna.radiowaves.left.and.right" : "wifi")
				}
			}
		}
		.disabled(isWorking)
		.confirmationDialog("\(title)?", isPresented: $isAsking, titleVisibility: .visible) {
			Button(title) {
				use()
			}
		} message: {
			if let ssid {
				Text("The controller leaves \(ControllerWiFi.name) and joins \(ssid). Every phone goes back to \(ssid) to control the lights.")
			} else {
				Text("The controller leaves \(console.node?.wifi ?? "its network") and runs \(ControllerWiFi.name). Every phone joins \(ControllerWiFi.name) to control the lights.")
			}
		}
		.alert("Could Not Switch", isPresented: Binding { failure != nil } set: { _ in failure = nil }) {
			Button("OK", role: .cancel) { failure = nil }
		} message: {
			Text(failure ?? "")
		}
	}
	
	private var title: String {
		ssid.map { "Use \($0)" } ?? "Use Controller’s Wi-Fi"
	}
	
	private func use() {
		isWorking = true
		Task {
			if let ssid {
				failure = await ControllerWiFi.rejoin(ssid, console: console)
			} else {
				failure = await ControllerWiFi.use(console: console)
			}
			isWorking = false
		}
	}
}
