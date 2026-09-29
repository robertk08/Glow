import SwiftData
import SwiftUI

struct RootView: View {
	@Environment(Console.self) private var console
	@Environment(FixtureLibrary.self) private var library
	@Environment(ShowLibrary.self) private var shows
	@Environment(\.horizontalSizeClass) private var sizeClass
	@Environment(\.scenePhase) private var scenePhase
	@Environment(\.modelContext) private var context
	@Query(sort: \Fixture.sortIndex) private var fixtures: [Fixture]
	@Query(sort: \Look.sortIndex) private var looks: [Look]
	
	@State private var section = "lights"
	@State private var returning: String?
	@State private var naming = ""
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
		.tabBarMinimizeBehavior(.never)
	}
	
	var body: some View {
		@Bindable var selection = console.selection
		
		return Group {
			if shows.standby.isBlank, !shows.isLoaded {
				Color.clear
			} else if !shows.isLoaded {
				WaitingView()
			} else if sizeClass == .compact {
				tabs
					.tabViewBottomAccessory {
						if section == "scenes" {
							SceneBar(transition: transition)
						} else {
							ConsoleBar(transition: transition)
						}
					}
					.sheet(isPresented: $selection.isProgrammerOpen) {
						ProgrammerView(programmer: console.programmer(among: fixtures, library: library), isSheet: true)
							.presentationDetents([.fraction(0.5), .large])
							.presentationBackgroundInteraction(.enabled(upThrough: .fraction(0.5)))
							.presentationDragIndicator(.visible)
							.navigationTransition(.zoom(sourceID: "programmer", in: transition))
					}
					.sheet(isPresented: $selection.isSceneOpen) {
						if let look = looks.first(where: { $0.identifier == console.selection.scene }) {
							SceneView(look: look, isSheet: true)
								.id(look.identifier)
								.presentationDetents([.fraction(0.5), .large])
								.presentationBackgroundInteraction(.enabled(upThrough: .fraction(0.5)))
								.presentationDragIndicator(.visible)
								.navigationTransition(.zoom(sourceID: "scene", in: transition))
						}
					}
			} else {
				tabs
					.inspector(isPresented: .constant(section != "settings")) {
						Group {
							if section == "scenes" {
								SceneInspector()
							} else {
								ProgrammerView(programmer: console.programmer(among: fixtures, library: library))
							}
						}
						.inspectorColumnWidth(min: 360, ideal: 420, max: 520)
					}
			}
		}
		.alert("New Scene", isPresented: $selection.isNaming) {
			TextField(Look.suggestedName(among: looks), text: $naming)
				.autocorrectionDisabled()
			
			Button("Cancel", role: .cancel) {
				naming = ""
			}
			
			Button("Create") {
				console.selection.building = Look.fresh(among: looks, named: naming, context: context).identifier
				naming = ""
			}
		}
		.sensoryFeedback(.impact(weight: .medium), trigger: console.commands)
		.task {
			shows.reach(console, library: library)
		}
		.onChange(of: console.link) {
			shows.reach(console, library: library)
		}
		.onChange(of: console.node) {
			shows.reach(console, library: library)
		}
		.onChange(of: looks.map(\.identifier)) {
			if !looks.contains(where: { $0.identifier == console.selection.scene }) { console.selection.isSceneOpen = false }
		}
		.onChange(of: console.selection.building) { before, after in
			if before == nil, after != nil {
				returning = section
				section = "lights"
			} else if after == nil, let returning {
				section = returning
				self.returning = nil
			}
		}
		.onChange(of: scenePhase) {
			shows.settle(scenePhase)
		}
		.onChange(of: shows.refusal) {
			guard let refusal = shows.refusal, let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene, var top = scene.keyWindow?.rootViewController else { return }
			
			while let next = top.presentedViewController {
				top = next
			}
			
			let alert = UIAlertController(title: refusal.title, message: refusal.message, preferredStyle: .alert)
			alert.addAction(UIAlertAction(title: "OK", style: .cancel) { _ in
				shows.refusal = nil
			})
			top.present(alert, animated: true)
		}
	}
}
