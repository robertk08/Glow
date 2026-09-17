import SwiftUI

struct NodeSetupView: View {
	@Environment(Console.self) private var console
	@Environment(\.dismiss) private var dismiss
	@Environment(\.openURL) private var openURL
	
	@State private var model = NodeSetupModel()
	
	var body: some View {
		@Bindable var model = model
		
		return NavigationStack {
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
				if let failure = model.failure {
					Text(failure)
				} else {
					Text("Waiting for the controller…")
				}
			}
		}
		.task {
			await model.waitForController()
		}
	}
	
	private var chooseNetwork: some View {
		List {
			if model.networks.isEmpty {
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
									await model.join(console: console)
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
				SecureField("Password", text: $model.password)
					.submitLabel(.join)
					.onSubmit {
						Task {
							await model.join(console: console)
						}
					}
			} header: {
				Text(model.selected?.ssid ?? "")
			}
			
			Section {
				Button("Join") {
					Task {
						await model.join(console: console)
					}
				}
				.disabled(model.password.isEmpty)
			}
		}
	}
	
	private var joining: some View {
		List {
			Section {
				HStack {
					Text("Joining \(model.selected?.ssid ?? "")")
					Spacer()
					ProgressView()
				}
			} footer: {
				if let failure = model.failure {
					Text(failure)
				} else {
					Text("The controller leaves its own network now, so your iPhone will drop back to your usual Wi-Fi.")
				}
			}
		}
	}
	
	private var done: some View {
		ContentUnavailableView {
			Label("Ready", systemImage: "checkmark.circle")
		} description: {
			Text("The controller is on \(model.selected?.ssid ?? "your network").")
		} actions: {
			Button("Done") { dismiss() }
				.buttonStyle(.borderedProminent)
		}
	}
}
