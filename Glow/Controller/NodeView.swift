import SwiftUI

struct NodeView: View {
	@Environment(Console.self) private var console
	@Environment(NodeDiscovery.self) private var discovery
	
	@State private var isSettingUp = false
	@State private var isForgetting = false
	@State private var failure: String?
	
	var body: some View {
		let endpoints = discovery.controllers(endpoint: console.endpoint, nodeID: console.node?.id)
		let selection = console.node?.id ?? console.endpoint.id
		
		List {
			Section {
				LabeledContent {
					Text(console.link.summary(latency: console.latency))
						.foregroundStyle(console.link.tint)
				} label: {
					Label {
						Text("Status")
					} icon: {
						Image(systemName: console.link.symbol)
							.foregroundStyle(console.link.tint)
					}
				}
				
				LabeledContent("Address", value: console.endpoint.host)
					.textSelection(.enabled)
				
				if let node = console.node {
					LabeledContent("Name", value: node.name)
					LabeledContent("Firmware", value: node.firmware)
				}
			} footer: {
				Text(console.link.explanation)
			}
			
			Section {
				Button("Change Wi-Fi Network", systemImage: "wifi.router") {
					isSettingUp = true
				}
			} footer: {
				Text("Nothing is ever typed on the controller, Wi-Fi included. Glow joins its setup network, reads the list of networks it can see, takes the password from you and hands it over.")
			}
			
			Section {
				if discovery.endpoints.isEmpty {
					HStack {
						Text("Looking for controllers")
						Spacer()
						ProgressView()
					}
					.foregroundStyle(.secondary)
				} else {
					Picker("Controller", selection: Binding { selection } set: { id in
						guard let found = endpoints.first(where: { $0.id == id }) else { return }
						console.endpoint = found
					}) {
						ForEach(endpoints) { endpoint in
							Text(endpoint.name).tag(endpoint.id)
						}
					}
					.pickerStyle(.inline)
					.labelsHidden()
				}
			} header: {
				Text("On This Network")
			} footer: {
				Text("Glow finds controllers over Bonjour. If yours is missing, it is on another network or still coming up.")
			}
			
			Section {
				Button("Forget Wi-Fi Network", systemImage: "trash", role: .destructive) {
					isForgetting = true
				}
				.disabled(!console.link.isConnected)
			} footer: {
				Text("The controller drops the network it stored and raises Glow Setup again. Reflashing does not erase it, this does.")
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
		.onDisappear {
			discovery.stop()
		}
	}
}
