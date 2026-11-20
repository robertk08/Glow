import SwiftUI

struct NodeSetupView: View {
	@Environment(Console.self) private var console
	
	@State private var model = NodeSetupModel()
	
	var body: some View {
		@Bindable var model = model
		
		NavigationStack(path: $model.path) {
			FindingController(model: model)
				.navigationDestination(for: NodeSetupModel.Page.self) { page in
					switch page {
					case .networks: ChoosingNetwork(model: model)
					case .password: EnteringPassword(model: model)
					case .joining, .own: Joining(model: model, page: page)
					}
				}
		}
		.task {
			await model.waitForController(console: console)
		}
		.onDisappear(perform: model.leave)
		.interactiveDismissDisabled(model.isWorking)
	}
}

private struct FindingController: View {
	@Environment(Console.self) private var console
	@Environment(\.openURL) private var openURL
	
	let model: NodeSetupModel
	
	var body: some View {
		Group {
			if let failure = model.failure {
				ContentUnavailableView {
					Label("Can't Reach \(ControllerWiFi.name)", systemImage: "wifi.exclamationmark")
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
					
					Button("Open Wi-Fi Settings") {
						guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
						openURL(url)
					}
				}
			} else {
				Working(label: Label("Joining \(ControllerWiFi.name)", systemImage: "wifi.router"), text: Text("Keep the controller powered on and allow the Wi-Fi connection when asked. Nothing needs to be typed on the controller."))
			}
		}
		.navigationTitle("Set Up Controller")
		.navigationBarTitleDisplayMode(.inline)
		.toolbar {
			CloseButton()
		}
	}
}

private struct ChoosingNetwork: View {
	let model: NodeSetupModel
	
	var body: some View {
		Group {
			if let failure = model.failure, model.networks.isEmpty {
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
				Working(label: Label("Looking for Networks", systemImage: "antenna.radiowaves.left.and.right"), text: Text("The controller is scanning the air around it. This takes a few seconds."))
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
					
					Section {
						Button("Use Controller’s Wi-Fi", systemImage: "antenna.radiowaves.left.and.right") {
							model.push(.own)
						}
					} footer: {
						Text("Phones join \(ControllerWiFi.name) to control the lights.")
					}
				}
			}
		}
		.navigationTitle("Wi-Fi")
		.navigationBarTitleDisplayMode(.inline)
		.navigationBarBackButtonHidden()
		.toolbar {
			CloseButton()
		}
		.task {
			guard model.networks.isEmpty else { return }
			await model.loadNetworks()
		}
	}
}

private struct EnteringPassword: View {
	let model: NodeSetupModel
	
	@FocusState private var isFocused: Bool
	
	var body: some View {
		@Bindable var model = model
		
		Form {
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
					model.push(.joining)
				}
		}
		.navigationTitle(model.selected?.ssid ?? "")
		.navigationBarTitleDisplayMode(.inline)
		.toolbar {
			ToolbarItem(placement: .confirmationAction) {
				Button("Join") {
					model.push(.joining)
				}
				.disabled(!model.canJoin)
			}
		}
		.task {
			isFocused = true
		}
	}
}

private struct Joining: View {
	@Environment(Console.self) private var console
	
	let model: NodeSetupModel
	let page: NodeSetupModel.Page
	
	var body: some View {
		let name = page == .own ? ControllerWiFi.name : model.selected?.ssid ?? ""
		
		Group {
			if model.isDone {
				ContentUnavailableView {
					Label("Ready", systemImage: "checkmark.circle.fill")
						.foregroundStyle(.green)
				} description: {
					Text("The controller is on \(name).")
				} actions: {
					Button("Done") {
						console.selection.isSetupOpen = false
					}
					.font(.headline)
					.buttonStyle(.glassProminent)
					.controlSize(.large)
				}
				.sensoryFeedback(.success, trigger: model.isDone)
			} else if let failure = model.failure {
				ContentUnavailableView {
					Label("The Join Did Not Finish", systemImage: "exclamationmark.triangle")
				} description: {
					Text(failure)
				} actions: {
					Button("Try Again") {
						model.failure = nil
					}
					.buttonStyle(.glassProminent)
					.controlSize(.large)
				}
			} else {
				Working(label: Label("Joining \(name)", systemImage: "wifi.router"), text: Text("Keep the app open and allow the Wi-Fi connection when asked."))
			}
		}
		.navigationTitle(name)
		.navigationBarTitleDisplayMode(.inline)
		.navigationBarBackButtonHidden(model.failure == nil)
		.task(id: model.failure == nil) {
			guard model.failure == nil, !model.isDone else { return }
			
			if page == .own {
				await model.useOwn(console: console)
			} else {
				await model.join(console: console)
			}
		}
	}
}

private struct CloseButton: ToolbarContent {
	@Environment(Console.self) private var console
	
	var body: some ToolbarContent {
		ToolbarItem(placement: .cancellationAction) {
			Button(role: .close) {
				console.selection.isSetupOpen = false
			}
		}
	}
}

private struct Working: View {
	let label: Label<Text, Image>
	let text: Text
	
	var body: some View {
		ContentUnavailableView {
			label
		} description: {
			text
		} actions: {
			ProgressView()
				.controlSize(.large)
		}
	}
}
