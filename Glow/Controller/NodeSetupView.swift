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
				case .findController: FindingController(model: model)
				case .chooseNetwork: ChoosingNetwork(model: model)
				case .password: EnteringPassword(model: model)
				case .joining: Joining(model: model)
				case .done: Finished(model: model)
				}
			}
			.navigationTitle("Controller Setup")
			.navigationBarTitleDisplayMode(.inline)
			.toolbar {
				ToolbarItem(placement: .cancellationAction) {
					Button(role: .close) { dismiss() }
				}
				
				if model.step != .done, model.failure != nil {
					ToolbarItem(placement: .topBarTrailing) {
						Button("Open Wi-Fi Settings") {
							guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
							openURL(url)
						}
						.font(.footnote)
					}
				}
			}
		}
		.presentationDetents([.large])
		.interactiveDismissDisabled(model.step == .joining && model.failure == nil)
	}
}

private struct FindingController: View {
	@Environment(Console.self) private var console
	
	let model: NodeSetupModel
	
	var body: some View {
		Group {
			if let failure = model.failure {
				ContentUnavailableView {
					Label("Can't Reach Glow Setup", systemImage: "wifi.exclamationmark")
				} description: {
					Text(failure)
				} actions: {
					Button("Try Again") {
						Task {
							await model.waitForController(console: console)
						}
					}
					.buttonStyle(.glassProminent)
					.controlSize(.large)
				}
			} else {
				ContentUnavailableView {
					Label("Joining Glow Setup", systemImage: "wifi.router")
				} description: {
					Text("Keep the controller powered on and allow the Wi-Fi connection when asked. Nothing needs to be typed on the controller.")
				} actions: {
					ProgressView()
						.controlSize(.large)
				}
			}
		}
		.task {
			await model.waitForController(console: console)
		}
	}
}

private struct ChoosingNetwork: View {
	let model: NodeSetupModel
	
	var body: some View {
		Group {
			if let failure = model.failure {
				ContentUnavailableView {
					Label("No Networks Came Back", systemImage: "antenna.radiowaves.left.and.right.slash")
				} description: {
					Text(failure)
				} actions: {
					Button("Scan Again") {
						Task {
							await model.loadNetworks()
						}
					}
					.buttonStyle(.glassProminent)
					.controlSize(.large)
				}
			} else if model.networks.isEmpty {
				ContentUnavailableView {
					Label("Looking for Networks", systemImage: "antenna.radiowaves.left.and.right")
				} description: {
					Text("The controller is scanning the air around it. This takes a few seconds.")
				} actions: {
					ProgressView()
						.controlSize(.large)
				}
			} else {
				List {
					Section {
						ForEach(model.networks) { network in
							Button {
								model.choose(network: network)
							} label: {
								LabeledContent {
									HStack(spacing: 6) {
										if network.secure {
											Image(systemName: "lock.fill")
												.font(.footnote)
										}
										
										Image(systemName: "wifi", variableValue: Double(network.bars) / 3)
									}
									.foregroundStyle(.secondary)
								} label: {
									Text(network.ssid)
										.foregroundStyle(.primary)
								}
								.contentShape(.rect)
							}
							.buttonStyle(.plain)
						}
					} header: {
						Text("Networks the controller can see")
					} footer: {
						Text("Only 2.4 GHz. The controller has no 5 GHz radio, so a 5 GHz-only network never appears here.")
					}
					
					Section {
						Button("Scan Again", systemImage: "arrow.clockwise") {
							Task {
								await model.loadNetworks()
							}
						}
					}
				}
			}
		}
		.task {
			await model.loadNetworks()
		}
	}
}

private struct EnteringPassword: View {
	let model: NodeSetupModel
	
	@FocusState private var isFocused: Bool
	
	var body: some View {
		@Bindable var model = model
		
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
					.focused($isFocused)
					.onSubmit {
						guard model.canJoin else { return }
						model.step = .joining
					}
			} header: {
				Text(model.selected?.ssid ?? "")
			} footer: {
				if let failure = model.failure {
					Text(failure)
						.foregroundStyle(.orange)
				} else {
					Text("Glow hands this to the controller and never stores it. The controller writes it only once the join succeeds, so a wrong password cannot displace a network that works.")
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
		.task {
			isFocused = true
		}
	}
}

private struct Joining: View {
	@Environment(Console.self) private var console
	@Environment(NodeDiscovery.self) private var discovery
	
	let model: NodeSetupModel
	
	var body: some View {
		Group {
			if let failure = model.failure {
				ContentUnavailableView {
					Label("The Join Did Not Finish", systemImage: "exclamationmark.triangle")
				} description: {
					Text(failure)
				} actions: {
					Button("Pick Another Network") {
						model.failure = nil
						model.step = .chooseNetwork
					}
					.buttonStyle(.glassProminent)
					.controlSize(.large)
					
					Button("Try the Same Network Again") {
						model.failure = nil
						model.step = .joining
					}
				}
			} else {
				ContentUnavailableView {
					Label("Joining \(model.selected?.ssid ?? "")", systemImage: "wifi.router")
				} description: {
					Text("The controller is joining your network and Glow is moving over with it. Keep the app open and allow the Wi-Fi connection when asked.")
				} actions: {
					ProgressView()
						.controlSize(.large)
				}
			}
		}
		.task(id: model.failure == nil) {
			guard model.failure == nil else { return }
			await model.join(console: console, discovery: discovery)
		}
	}
}

private struct Finished: View {
	@Environment(Console.self) private var console
	@Environment(\.dismiss) private var dismiss
	
	let model: NodeSetupModel
	
	var body: some View {
		ContentUnavailableView {
			Label("Ready", systemImage: "checkmark.circle.fill")
				.foregroundStyle(.green)
		} description: {
			Text(model.failure ?? "The controller is on \(model.selected?.ssid ?? "your network") at \(console.endpoint.host). Nothing was typed on it.")
		} actions: {
			Button("Done", systemImage: "checkmark") {
				dismiss()
			}
			.font(.headline)
			.buttonStyle(.glassProminent)
			.controlSize(.large)
		}
		.sensoryFeedback(.success, trigger: model.step)
	}
}
