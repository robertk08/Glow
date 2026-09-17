import SwiftData
import SwiftUI

struct RootView: View {
	@Environment(Console.self) private var console
	@Environment(FixtureLibrary.self) private var library
	@Environment(\.horizontalSizeClass) private var sizeClass
	@Environment(\.modelContext) private var context
	@Query private var customProfiles: [CustomProfile]
	@Query(sort: \Fixture.sortIndex) private var fixtures: [Fixture]
	
	@State private var section: Section? = .lights
	@Namespace private var transition
	
	enum Section: String, CaseIterable, Identifiable {
		case lights, scenes, settings
		
		var id: String { rawValue }
		
		var name: String { rawValue.capitalized }
		
		var symbol: String {
			switch self {
			case .lights: "lightbulb"
			case .scenes: "theatermasks"
			case .settings: "gearshape"
			}
		}
	}
	
	@ViewBuilder private var destination: some View {
		switch section {
		case .scenes: ScenesView()
		case .settings: SettingsView()
		default: LightsView()
		}
	}
	
	private var columns: some View {
		@Bindable var console = console
		
		return NavigationSplitView {
			List(selection: $section) {
				ForEach(Section.allCases) { item in
					Label(item.name, systemImage: item.symbol)
						.tag(item)
				}
			}
			.navigationTitle("Glow")
		} detail: {
			NavigationStack {
				destination
					.toolbar {
						ToolbarItem(placement: .bottomBar) {
							MasterBar()
						}
						
						ToolbarSpacer(.fixed, placement: .bottomBar)
						
						ToolbarItem(placement: .bottomBar) {
							ClearButton()
						}
					}
			}
			.inspector(isPresented: $console.isInspectingSelection) {
				ProgrammerView(programmer: console.programmer(among: fixtures, library: library))
					.inspectorColumnWidth(min: 320, ideal: 380, max: 480)
			}
		}
	}
	
	private var tabs: some View {
		@Bindable var console = console
		
		return TabView(selection: $section) {
			Tab(Section.lights.name, systemImage: Section.lights.symbol, value: Optional(Section.lights)) {
				NavigationStack {
					LightsView()
				}
			}
			
			Tab(Section.scenes.name, systemImage: Section.scenes.symbol, value: Optional(Section.scenes)) {
				NavigationStack {
					ScenesView()
				}
			}
			
			Tab(Section.settings.name, systemImage: Section.settings.symbol, value: Optional(Section.settings)) {
				NavigationStack {
					SettingsView()
				}
			}
		}
		.tabBarMinimizeBehavior(.onScrollDown)
		.tabViewBottomAccessory {
			ConsoleBar(transition: transition)
		}
		.sheet(isPresented: $console.isProgrammerOpen) {
			ProgrammerView(programmer: console.programmer(among: fixtures, library: library))
				.presentationDetents([.fraction(0.5), .large])
				.presentationBackgroundInteraction(.enabled(upThrough: .fraction(0.5)))
				.presentationDragIndicator(.visible)
				.navigationTransition(.zoom(sourceID: "programmer", in: transition))
		}
	}
	
	var body: some View {
		Group {
			if sizeClass == .regular {
				columns
			} else {
				tabs
			}
		}
		.onChange(of: customProfiles) {
			library.setCustom(customProfiles.map(\.profile))
			console.prune(fixtures, library: library, context: context)
		}
		.task {
			library.setCustom(customProfiles.map(\.profile))
			console.prune(fixtures, library: library, context: context)
		}
	}
}
