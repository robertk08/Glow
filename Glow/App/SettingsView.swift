import SwiftUI

struct SettingsView: View {
	@Environment(Console.self) private var console
	@Environment(ShowLibrary.self) private var shows
	
	var body: some View {
		List {
			Section {
				NavigationLink {
					NodeView()
				} label: {
					LabeledContent {
						Text(console.network)
							.foregroundStyle(.secondary)
					} label: {
						Label {
							Text("Controller")
						} icon: {
							Image(systemName: console.status.symbol)
								.foregroundStyle(console.status.tint)
						}
					}
				}
			} header: {
				Text("Connection")
			}
			
			Section {
				NavigationLink {
					ShowsView()
				} label: {
					LabeledContent {
						Text(shows.active.name)
							.foregroundStyle(.secondary)
					} label: {
						Label("Show", systemImage: "rectangle.stack")
					}
				}
				
				Toggle(isOn: Binding(get: { shows.active.sendsAllChannels }, set: { shows.sendAllChannels($0) })) {
					Label("Compatibility Mode", systemImage: "cable.connector")
				}
			} footer: {
				Text("Sends all 512 channels in this show, as a lighting desk does, for older fixtures like the Martin MAC 600.")
			}
			
			Section {
				NavigationLink {
					LibraryView()
				} label: {
					Label("Fixtures", systemImage: "books.vertical")
				}
				
				NavigationLink {
					MonitorView()
				} label: {
					Label("DMX Output", systemImage: "waveform")
				}
			} header: {
				Text("Fixtures and Output")
			}
			
			if shows.isDemo {
				Section {
					Button("Leave the Demo", systemImage: "rectangle.portrait.and.arrow.right", role: .destructive) {
						shows.stopDemo()
					}
				} footer: {
					Text("Nothing you changed in the demo was kept, and none of it reached a controller.")
				}
			} else {
				Section {
					Button("Explore a Demo", systemImage: "sparkles") {
						shows.startDemo()
					}
				} footer: {
					Text("Try things out without touching the lights or the show on the controller.")
				}
			}
			
			Section {
			} footer: {
				Text("Glow \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0") (\(Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"))")
					.textSelection(.enabled)
			}
		}
		.navigationTitle("Settings")
	}
}
