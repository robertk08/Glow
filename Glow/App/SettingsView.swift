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
			} header: {
				Text("Show")
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
			
			Section {
				LabeledContent("Version", value: "\(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0") (\(Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"))")
					.textSelection(.enabled)
			}
			
			if shows.isDemo {
				Section {
					Button("Leave the Demo", role: .destructive) {
						shows.stopDemo()
					}
				} footer: {
					Text("Nothing you changed in the demo was kept, and none of it reached a controller.")
				}
			}
		}
		.navigationTitle("Settings")
	}
}
