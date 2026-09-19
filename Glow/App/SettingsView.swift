import SwiftData
import SwiftUI

struct SettingsView: View {
	@Environment(Console.self) private var console
	@Environment(FixtureLibrary.self) private var library
	@Environment(ShowLibrary.self) private var shows
	@Query(sort: \Fixture.sortIndex) private var fixtures: [Fixture]
	@Query(sort: \FixtureGroup.sortIndex) private var groups: [FixtureGroup]
	@Query(sort: \Look.sortIndex) private var looks: [Look]
	
	var body: some View {
		List {
			Section {
				NavigationLink {
					NodeView()
				} label: {
					LinkCard()
				}
			} header: {
				Text("Controller")
			} footer: {
				Text(console.link.explanation)
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
				
				LabeledContent {
					Text("^[\(fixtures.count) light](inflect: true), ^[\(groups.count) group](inflect: true), ^[\(looks.count) scene](inflect: true)")
						.foregroundStyle(.secondary)
				} label: {
					Label("In this show", systemImage: "list.bullet")
				}
			} header: {
				Text("Show")
			} footer: {
				Text("A show holds its own patch, its groups, the fixtures you built and its scenes. Switching show swaps all of it at once, so a house rig and a touring rig never see each other.")
			}
			
			Section {
				NavigationLink {
					LibraryView()
				} label: {
					LabeledContent {
						Text("^[\(library.types.count) fixture](inflect: true)")
							.foregroundStyle(.secondary)
					} label: {
						Label("Fixtures", systemImage: "books.vertical")
					}
				}
				
				NavigationLink {
					MonitorView()
				} label: {
					LabeledContent {
						Text("\(library.channelsUsed(by: fixtures)) of \(Universe.channelCount)")
							.foregroundStyle(.secondary)
							.monospacedDigit()
					} label: {
						Label("DMX Output", systemImage: "waveform")
					}
				}
			} header: {
				Text("Rig")
			} footer: {
				Text("Fixtures is every definition Glow can patch, channel by channel, and where you build one of your own. DMX Output is what is going down the line right now.")
			}
			
			Section {
				LabeledContent("Version", value: "\(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0") (\(Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"))")
					.textSelection(.enabled)
			} footer: {
				Text("Glow sends DMX over Wi-Fi to an ESP32 controller. Your iPhone and the controller have to be on the same network.")
			}
		}
		.navigationTitle("Settings")
	}
}
