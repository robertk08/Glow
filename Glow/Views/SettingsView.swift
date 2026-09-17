import SwiftUI

struct SettingsView: View {
	@Environment(Console.self) private var console
	
	var body: some View {
		NavigationStack {
			List {
				Section {
					NavigationLink {
						NodeView()
					} label: {
						LabeledContent {
							Text(console.node?.name ?? console.link.name)
								.foregroundStyle(.secondary)
						} label: {
							Label("Controller", systemImage: "app.connected.to.app.below.fill")
						}
					}
				} footer: {
					Text("Glow sends to the controller over Wi-Fi. Your iPhone and the controller have to be on the same network.")
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
				} footer: {
					Text("Fixtures is every profile Glow can patch, channel by channel. DMX Output is what is going down the line right now.")
				}
				
				Section {
					LabeledContent("Version", value: "\(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0") (\(Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"))")
				}
			}
			.navigationTitle("Settings")
			.navigationBarTitleDisplayMode(.inline)
		}
	}
}
