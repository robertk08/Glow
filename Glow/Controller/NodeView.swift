import SwiftUI

struct NodeView: View {
	@Environment(Console.self) private var console
	
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
				
				if let usage = console.usage {
					LabeledContent("Memory", value: "\(usage.memory.formatted(.byteCount(style: .memory))) of \(usage.memoryTotal.formatted(.byteCount(style: .memory)))")
					LabeledContent("Storage", value: "\(usage.storage.formatted(.byteCount(style: .file))) of \(usage.storageTotal.formatted(.byteCount(style: .file)))")
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
				.confirmationDialog("Forget the network?", isPresented: $isForgetting, titleVisibility: .visible) {
					Button("Forget", role: .destructive) {
						Task {
							do {
								try await NodeStore().command("forget", at: console.reachable)
							} catch {
								failure = error.localizedDescription
							}
						}
					}
				} message: {
					Text("It restarts and you set it up from scratch.")
				}
			}
		}
		.navigationTitle("Controller")
		.navigationBarTitleDisplayMode(.inline)
		.sheet(isPresented: $isSettingUp) {
			NodeSetupView()
		}
		.alert("Could Not Forget Network", isPresented: Binding { failure != nil } set: { _ in failure = nil }) {
			Button("OK", role: .cancel) { failure = nil }
		} message: {
			Text(failure ?? "")
		}
	}
}
