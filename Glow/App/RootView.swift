import SwiftData
import SwiftUI

struct RootView: View {
	@Environment(Console.self) private var console
	@Environment(FixtureLibrary.self) private var library
	@Environment(\.horizontalSizeClass) private var sizeClass
	@Environment(\.modelContext) private var context
	@Query private var stored: [StoredFixtureType]
	@Query(sort: \Fixture.sortIndex) private var fixtures: [Fixture]
	
	@State private var section = "lights"
	@Namespace private var transition
	
	private var tabs: some View {
		TabView(selection: $section) {
			Tab("Lights", systemImage: "lightbulb", value: "lights") {
				NavigationStack {
					LightsView()
				}
			}
			
			Tab("Scenes", systemImage: "theatermasks", value: "scenes") {
				NavigationStack {
					ScenesView()
				}
			}
			
			Tab("Settings", systemImage: "gearshape", value: "settings") {
				NavigationStack {
					SettingsView()
				}
			}
		}
		.tabViewStyle(.sidebarAdaptable)
		.tabBarMinimizeBehavior(.onScrollDown)
		.tabViewBottomAccessory {
			ConsoleBar(transition: transition)
		}
	}
	
	var body: some View {
		@Bindable var console = console
		
		return Group {
			if sizeClass == .compact {
				tabs
					.sheet(isPresented: $console.isProgrammerOpen) {
						ProgrammerView(programmer: console.programmer(among: fixtures, library: library))
							.presentationDetents([.fraction(0.5), .large])
							.presentationBackgroundInteraction(.enabled(upThrough: .fraction(0.5)))
							.presentationDragIndicator(.visible)
							.navigationTransition(.zoom(sourceID: "programmer", in: transition))
					}
			} else {
				tabs
					.inspector(isPresented: $console.isProgrammerOpen) {
						ProgrammerView(programmer: console.programmer(among: fixtures, library: library))
							.inspectorColumnWidth(min: 360, ideal: 420, max: 520)
					}
			}
		}
		.onChange(of: console.selection) {
			if sizeClass == .regular { console.isProgrammerOpen = console.hasSelection }
		}
		.onChange(of: stored) {
			library.setMade(stored.map(\.definition))
			console.prune(fixtures, library: library, context: context)
		}
		.task {
			library.setMade(stored.map(\.definition))
			console.prune(fixtures, library: library, context: context)
		}
	}
}
