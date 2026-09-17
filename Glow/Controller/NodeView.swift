import SwiftUI

struct NodeView: View {
	@Environment(Console.self) private var console
	@Environment(NodeDiscovery.self) private var discovery
	
	@State private var isSettingUp = false
	@State private var isForgetting = false
	
	var body: some View {
		List {
			Section {
				LabeledContent {
					Text(console.link.summary(latency: console.latency))
						.foregroundStyle(console.link.isConnected ? Color.green : Color.orange)
				} label: {
					Label {
						Text("Status")
					} icon: {
						Image(systemName: console.link.isConnected ? "wifi" : "wifi.exclamationmark")
							.foregroundStyle(console.link.isConnected ? Color.green : Color.orange)
					}
				}
				
				LabeledContent("Address", value: console.endpoint.host)
				
				if let node = console.node {
					LabeledContent("Name", value: node.name)
					LabeledContent("Firmware", value: node.firmware)
				}
			}
			
			Section {
				Button("Change Wi-Fi Network", systemImage: "wifi.router") {
					isSettingUp = true
				}
			} footer: {
				Text("Nothing is entered on the controller itself. Glow hands it the network.")
			}
			
			Section {
				Button("Forget Wi-Fi Network", systemImage: "trash", role: .destructive) {
					isForgetting = true
				}
			} footer: {
				Text("The controller drops its stored network and raises Glow Setup again.")
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
						if !discovery.endpoints.contains(where: { $0.id == console.endpoint.id }) {
							Text(console.endpoint.name).tag(console.endpoint.id)
						}
						
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
			Text("It restarts and you set it up from scratch.")
		}
		.task {
			discovery.start()
		}
		.onDisappear {
			discovery.stop()
		}
	}
}
