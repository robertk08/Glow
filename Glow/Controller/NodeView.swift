import SwiftUI

struct NodeView: View {
	@Environment(Console.self) private var console
	
	@State private var isForgetting = false
	@State private var isProtecting = false
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
					UsageRow(title: "Memory", used: usage.memory, total: usage.memoryTotal, style: .memory)
					UsageRow(title: "Storage", used: usage.storage, total: usage.storageTotal, style: .file)
				}
			}
			
			Section {
				if console.link.isConnected, let node = console.node {
					LabeledContent("Wi-Fi", value: node.wifi.isEmpty ? ControllerWiFi.name : node.wifi)
				}
				
				Button("Connect Controller to Wi-Fi", systemImage: "wifi.router") {
					console.selection.isSetupOpen = true
				}
				
				if console.link.isConnected, let node = console.node, node.isOwn {
					if node.hasStored {
						UseWiFiButton(leaves: true, asks: true)
					}
				} else {
					UseWiFiButton(asks: console.link.isConnected && console.node?.wifi.isEmpty == false)
				}
			} header: {
				Text("Network")
			} footer: {
				if console.link.isConnected, let node = console.node {
					Text(node.isOwn ? "Phones join \(ControllerWiFi.name) to control the lights, up to five at once." : node.wifi.isEmpty ? "The controller can’t find its Wi-Fi, so phones join \(ControllerWiFi.name) for now." : "Phones on \(node.wifi) control the lights.")
				}
			}
			
			if console.link.isConnected, let node = console.node {
				Section {
					Button(node.passwordAction, systemImage: "lock") {
						console.passwordOutcome = nil
						isProtecting = true
					}
				}
				
				Section {
					Button("Forget Wi-Fi Network", systemImage: "trash", role: .destructive) {
						isForgetting = true
					}
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
		}
		.navigationTitle("Controller")
		.navigationBarTitleDisplayMode(.inline)
		.sheet(isPresented: $isProtecting) {
			PasswordView()
		}
		.alert("Could Not Forget Network", isPresented: Binding { failure != nil } set: { _ in failure = nil }) {
			Button("OK", role: .cancel) { failure = nil }
		} message: {
			Text(failure ?? "")
		}
	}
}

private struct UsageRow: View {
	let title: String
	let used: Int64
	let total: Int64
	let style: ByteCountFormatStyle.Style
	
	var body: some View {
		let share = total > 0 ? Double(used) / Double(total) : 0
		
		VStack(alignment: .leading, spacing: 8) {
			LabeledContent(title, value: "\(used.formatted(.byteCount(style: style))) of \(total.formatted(.byteCount(style: style)))")
			
			Gauge(value: min(share, 1)) {
				Text(title)
			}
			.gaugeStyle(.accessoryLinearCapacity)
			.labelsHidden()
			.tint(share > 0.9 ? .orange : .accentColor)
		}
		.accessibilityElement(children: .combine)
	}
}
