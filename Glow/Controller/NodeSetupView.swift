import SwiftUI

struct NodeSetupView: View {
	@Environment(Console.self) private var console
	@Environment(NodeDiscovery.self) private var discovery
	@Environment(\.dismiss) private var dismiss
	
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
				if model.failure != nil {
					Button("Try Again") {
						Task {
							await model.waitForController(console: console)
						}
					}
				} else {
					HStack {
						Text("Connecting to Glow Setup")
						Spacer()
						ProgressView()
					}
				}
			} footer: {
				Text(model.failure ?? "Keep the controller powered on. Allow Glow to join its setup network when asked. No credentials need to be entered on the controller.")
			}
		}
		.task {
			await model.waitForController(console: console)
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
					.textContentType(.password)
					.submitLabel(.join)
					.onSubmit {
						guard model.canJoin else { return }
						model.step = .joining
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
					model.step = .joining
				}
				.disabled(!model.canJoin)
				
				Button("Pick Another Network") {
					model.failure = nil
					model.step = .chooseNetwork
				}
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
				} footer: {
					Text("Glow is waiting for the controller to join your network. Keep the app open and allow the Wi-Fi connection when asked.")
				}
			}
		}
		.task {
			await model.join(console: console, discovery: discovery)
		}
	}
	
	private var done: some View {
		ContentUnavailableView {
			Label("Ready", systemImage: "checkmark.circle")
		} description: {
			Text(model.failure ?? "The controller is on \(model.selected?.ssid ?? "your network") at \(console.endpoint.host).")
		} actions: {
			Button("Done", systemImage: "checkmark") {
				dismiss()
			}
			.font(.headline)
			.buttonStyle(.glassProminent)
			.controlSize(.large)
		}
	}
}
