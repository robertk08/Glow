import SwiftUI

struct NodeView: View {
	@Environment(Console.self) private var console
	@Environment(NodeDiscovery.self) private var discovery
	
	@State private var isSettingUp = false
	@State private var isForgetting = false
	
	var body: some View {
		List {
			Section {
				LabeledContent("Status") {
					Label(console.link.summary(latency: console.latency), systemImage: console.link.isConnected ? "wifi" : "wifi.exclamationmark")
						.foregroundStyle(console.link.isConnected ? Color.green : Color.orange)
				}
				
				if let node = console.node {
					LabeledContent("Name", value: node.name)
					LabeledContent("Firmware", value: node.firmware)
				}
				
				LabeledContent("Address", value: console.endpoint.host)
			}
			
			Section {
				Button("Change Wi-Fi Network", systemImage: "wifi.router") {
					isSettingUp = true
				}
				
				Button("Forget Wi-Fi Network", systemImage: "trash", role: .destructive) {
					isForgetting = true
				}
			} footer: {
				Text("Nothing is entered on the controller itself. Glow hands it the network.")
			}
			
			Section("On This Network") {
				if discovery.endpoints.isEmpty {
					HStack {
						Text("Looking for controllers")
						Spacer()
						ProgressView()
					}
					.foregroundStyle(.secondary)
				} else {
					Picker("Controller", selection: Binding { console.endpoint.id } set: { id in
						guard let found = discovery.endpoints.first(where: { $0.id == id }) else { return }
						console.endpoint = found
					}) {
						ForEach(discovery.endpoints) { endpoint in
							Text(endpoint.name).tag(endpoint.id)
						}
					}
					.pickerStyle(.inline)
					.labelsHidden()
				}
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
					try? await NodeSetup(host: console.endpoint.host, port: console.endpoint.port).forget()
				}
			}
		} message: {
			Text("The controller restarts and makes its own Glow Setup network again.")
		}
		.task {
			discovery.start()
		}
		.onDisappear {
			discovery.stop()
		}
	}
}
