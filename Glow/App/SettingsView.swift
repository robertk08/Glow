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
						Text(console.link.name)
							.foregroundStyle(.secondary)
					} label: {
						Label {
							Text("Controller")
						} icon: {
							Image(systemName: console.link.symbol)
								.foregroundStyle(console.link.tint)
						}
					}
				}
			} header: {
				Text("Connection")
			} footer: {
				Text("Glow sends to the controller over Wi-Fi. Your iPhone and the controller have to be on the same network.")
			}
			
			Section {
				NavigationLink {
					ShowsView()
				} label: {
					LabeledContent {
						Text(shows.active.name)
							.foregroundStyle(.secondary)
					} label: {
						Label("Show", systemImage: "theatermasks")
					}
				}
			} header: {
				Text("Show")
			} footer: {
				Text("A show holds its own patch, groups, built fixtures and scenes.")
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
			} footer: {
				Text("Fixtures is every definition Glow can patch, channel by channel. DMX Output is what is going down the line right now.")
			}
			
			Section {
				LabeledContent("Version", value: "\(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0") (\(Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"))")
					.textSelection(.enabled)
			}
		}
		.navigationTitle("Settings")
	}
}
