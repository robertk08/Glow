import SwiftUI

struct NodeSetupView: View {
	@Environment(Console.self) private var console
	@Environment(NodeDiscovery.self) private var discovery
	@Environment(\.dismiss) private var dismiss
	@Environment(\.openURL) private var openURL
	
	@State private var model = NodeSetupModel()
	
	var body: some View {
		NavigationStack {
			Group {
				switch model.step {
				case .findController: findController
				case .chooseNetwork: chooseNetwork
				case .password: passwordEntry
				case .joining: joining
				case .done: done
				}
			}
			.navigationTitle("Wi-Fi Setup")
			.navigationBarTitleDisplayMode(.inline)
			.toolbar {
				Button(role: .close) { dismiss() }
			}
		}
	}
	
	private var findController: some View {
		List {
			Section {
				Text("Open Wi-Fi settings and join the network called **Glow Setup**, then come back. Your iPhone will say it has no internet, which is expected.")
				
				Button("Open Wi-Fi Settings") {
					if let url = URL(string: UIApplication.openSettingsURLString) {
						openURL(url)
					}
				}
			} footer: {
				Text("Waiting for the controller…")
			}
		}
		.task {
			await model.waitForController()
		}
	}
	
	private var chooseNetwork: some View {
		List {
			if let failure = model.failure {
				Section {
					Button("Try Again") {
						Task {
							await model.loadNetworks()
						}
					}
				} footer: {
					Text(failure)
				}
			} else if model.networks.isEmpty {
				Section {
					HStack {
						Text("Looking for networks")
						Spacer()
						ProgressView()
					}
				}
			} else {
				Section {
					ForEach(model.networks) { network in
						Button {
							model.choose(network: network)
							
							if !network.secure {
								Task {
									await model.join(console: console, discovery: discovery)
								}
							}
						} label: {
							LabeledContent {
								HStack(spacing: 6) {
									if network.secure {
										Image(systemName: "lock.fill")
									}
									Image(systemName: "wifi", variableValue: Double(network.bars) / 3)
								}
								.foregroundStyle(.secondary)
							} label: {
								Text(network.ssid)
							}
							.contentShape(.rect)
						}
						.buttonStyle(.plain)
					}
				} footer: {
					Text("These are the networks the controller can see. It only works on 2.4 GHz.")
				}
			}
		}
		.task {
			await model.loadNetworks()
		}
	}
	
	private var passwordEntry: some View {
		List {
			Section {
				if model.selected?.enterprise == true {
					TextField("Username", text: $model.user)
						.textContentType(.username)
						.textInputAutocapitalization(.never)
						.autocorrectionDisabled()
				}
				
				SecureField("Password", text: $model.password)
					.submitLabel(.join)
					.onSubmit {
						Task {
							await model.join(console: console, discovery: discovery)
						}
					}
			} header: {
				Text(model.selected?.ssid ?? "")
			} footer: {
				if let failure = model.failure {
					Text(failure)
				}
			}
			
			Section {
				Button("Join") {
					Task {
						await model.join(console: console, discovery: discovery)
					}
				}
				.disabled(!model.canJoin)
			}
		}
	}
	
	private var joining: some View {
		List {
			if let failure = model.failure {
				Section {
					Button("Pick Another Network") {
						model.failure = nil
						model.step = .chooseNetwork
					}
				} footer: {
					Text(failure)
				}
			} else {
				Section {
					HStack {
						Text("Joining \(model.selected?.ssid ?? "")")
						Spacer()
						ProgressView()
					}
					
					Button("Open Wi-Fi Settings") {
						if let url = URL(string: UIApplication.openSettingsURLString) {
							openURL(url)
						}
					}
				} footer: {
					Text("The controller has left Glow Setup, so your iPhone needs to be back on your usual Wi-Fi for Glow to find it again.")
				}
			}
		}
	}
	
	private var done: some View {
		ContentUnavailableView {
			Label("Ready", systemImage: "checkmark.circle")
		} description: {
			Text("The controller is on \(model.selected?.ssid ?? "your network") at \(console.endpoint.host). Put your iPhone back on that network to control it.")
		} actions: {
			Button("Done") { dismiss() }
				.buttonStyle(.borderedProminent)
		}
	}
}
