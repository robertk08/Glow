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
	
	static func leave(console: Console) async -> String? {
		do {
			try await NodeStore().command("stored", at: console.reachable)
		} catch {
			return "The controller did not switch. Check the connection and try again."
		}
		
		console.endpoint = .fallback
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

struct UseWiFiButton: View {
	@Environment(Console.self) private var console
	
	var leaves = false
	let asks: Bool
	
	@State private var isAsking = false
	@State private var isWorking = false
	@State private var failure: String?
	
	var body: some View {
		Button(role: leaves ? .destructive : nil) {
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
					Image(systemName: leaves ? "wifi" : "antenna.radiowaves.left.and.right")
				}
			}
		}
		.tint(leaves ? .red : nil)
		.disabled(isWorking)
		.confirmationDialog("\(title)?", isPresented: $isAsking, titleVisibility: .visible) {
			Button(title, role: leaves ? .destructive : nil) {
				use()
			}
		} message: {
			if leaves {
				Text("The controller goes back to its Wi-Fi network. If it can’t find it within a minute, it runs \(ControllerWiFi.name) again.")
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
		leaves ? "Stop Using Controller’s Wi-Fi" : "Use Controller’s Wi-Fi"
	}
	
	private func use() {
		isWorking = true
		Task {
			if leaves {
				failure = await ControllerWiFi.leave(console: console)
			} else {
				failure = await ControllerWiFi.use(console: console)
			}
			isWorking = false
		}
	}
}
