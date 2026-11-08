import NetworkExtension
import SwiftUI

enum ControllerWiFi {
	static let name = "Glow Setup"
	
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

struct UseControllerWiFiButton: View {
	@Environment(Console.self) private var console
	
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
				Text("Use Controller’s Wi-Fi")
			} icon: {
				if isWorking {
					ProgressView()
				} else {
					Image(systemName: "antenna.radiowaves.left.and.right")
				}
			}
		}
		.disabled(isWorking)
		.confirmationDialog("Use Controller’s Wi-Fi?", isPresented: $isAsking, titleVisibility: .visible) {
			Button("Use Controller’s Wi-Fi") {
				use()
			}
		} message: {
			Text("The controller leaves \(console.node?.wifi ?? "its network") and runs \(ControllerWiFi.name). Every phone joins \(ControllerWiFi.name) to control the lights.")
		}
		.alert("Could Not Switch", isPresented: Binding { failure != nil } set: { _ in failure = nil }) {
			Button("OK", role: .cancel) { failure = nil }
		} message: {
			Text(failure ?? "")
		}
	}
	
	private func use() {
		isWorking = true
		Task {
			failure = await ControllerWiFi.use(console: console)
			isWorking = false
		}
	}
}
