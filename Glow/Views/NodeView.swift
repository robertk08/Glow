import SwiftUI

struct NodeView: View {
	@Environment(Console.self) private var console
	@Environment(NodeDiscovery.self) private var discovery
	
	@State private var isSettingUp = false
	@State private var manualHost = ""
	@State private var isForgetting = false
	
	var body: some View {
		List {
			Section {
				LabeledContent("Status", value: console.link.summary(latency: console.latency))
				
				if let node = console.node {
					LabeledContent("Name", value: node.name)
				}
				
				LabeledContent("Address", value: console.endpoint.host)
			}
			
			Section {
				Button("Identify") {
					console.identify()
				}
				.disabled(!console.link.isConnected)
				
				Button("Change Wi-Fi Network") {
					isSettingUp = true
				}
				.sheet(isPresented: $isSettingUp) {
					NodeSetupView()
				}
				
				Button("Forget Wi-Fi Network", role: .destructive) {
					isForgetting = true
				}
				.confirmationDialog("Forget the network?", isPresented: $isForgetting, titleVisibility: .visible) {
					Button("Forget", role: .destructive) {
						Task { try? await NodeSetup(host: console.endpoint.host, port: console.endpoint.port).forget() }
					}
				} message: {
					Text("The controller restarts and makes its own Glow Setup network again.")
				}
			} footer: {
				Text("Identify flashes the lights so you can tell which controller you are talking to.")
			}
			
			if !discovery.endpoints.isEmpty {
				Section("On This Network") {
					ForEach(discovery.endpoints) { endpoint in
						Button {
							console.endpoint = endpoint
						} label: {
							LabeledContent {
								if endpoint.id == console.endpoint.id {
									Image(systemName: "checkmark")
								}
							} label: {
								Text(endpoint.name)
							}
							.contentShape(.rect)
						}
						.buttonStyle(.plain)
					}
				}
			}
			
			Section {
				TextField("Address", text: $manualHost)
					.textInputAutocapitalization(.never)
					.autocorrectionDisabled()
					.onSubmit {
						guard let endpoint = NodeEndpoint(entry: manualHost) else { return }
						console.endpoint = endpoint
					}
			} header: {
				Text("Connect By Address")
			} footer: {
				Text("Only needed if the controller does not show up by itself.")
			}
		}
		.navigationTitle("Controller")
		.navigationBarTitleDisplayMode(.inline)
		.task {
			discovery.start()
			manualHost = console.endpoint.host
		}
		.onDisappear { discovery.stop() }
	}
}
