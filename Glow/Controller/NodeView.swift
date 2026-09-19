import SwiftUI

struct NodeView: View {
	@Environment(Console.self) private var console
	@Environment(NodeDiscovery.self) private var discovery
	
	@State private var isSettingUp = false
	@State private var isForgetting = false
	@State private var failure: String?
	
	var body: some View {
		List {
			Section {
				LabeledContent {
					Text(console.link.summary(latency: console.latency))
						.foregroundStyle(console.link.tint)
				} label: {
					Text("Status")
				}
				
				if let node = console.node {
					LabeledContent("Firmware", value: node.firmware)
				}
			}
			
			Section {
				Button("Change Wi-Fi Network", systemImage: "wifi.router") {
					isSettingUp = true
				}
				
				Button("Forget Wi-Fi Network", systemImage: "trash", role: .destructive) {
					isForgetting = true
				}
				.foregroundStyle(.red)
				.disabled(!console.link.isConnected)
			}
		}
		.navigationTitle("Controller")
		.navigationBarTitleDisplayMode(.inline)
		.sheet(isPresented: $isSettingUp) {
			NodeSetupView()
		}
		.confirmationDialog("Forget the network?", isPresented: $isForgetting, titleVisibility: .visible) {
			Button("Forget", role: .destructive) {
				Task {
					do {
						try await NodeSetup(host: console.endpoint.host, port: console.endpoint.port).forget()
					} catch {
						failure = error.localizedDescription
					}
				}
			}
		} message: {
			Text("It restarts and you set it up from scratch.")
		}
		.alert("Could Not Forget Network", isPresented: Binding { failure != nil } set: { _ in failure = nil }) {
			Button("OK", role: .cancel) { failure = nil }
		} message: {
			Text(failure ?? "")
		}
		.task {
			discovery.start()
		}
		.onChange(of: discovery.endpoints) {
			guard !console.link.isConnected, let found = discovery.endpoints.first else { return }
			console.endpoint = found
		}
		.onDisappear {
			discovery.stop()
		}
	}
}
