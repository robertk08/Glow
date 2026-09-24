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
						ConsoleBar(transition: transition)
					}
					.sheet(isPresented: $selection.isProgrammerOpen) {
						ProgrammerView(programmer: console.programmer(among: fixtures, library: library), isSheet: true)
							.presentationDetents([.fraction(0.5), .large])
							.presentationBackgroundInteraction(.enabled(upThrough: .fraction(0.5)))
							.presentationDragIndicator(.visible)
							.navigationTransition(.zoom(sourceID: "programmer", in: transition))
					}
			} else {
				tabs
					.inspector(isPresented: .constant(section == "lights")) {
						VStack(spacing: 0) {
							ProgrammerView(programmer: console.programmer(among: fixtures, library: library))

							Divider()

							MasterBar()
								.padding(.vertical, 10)
						}
						.inspectorColumnWidth(min: 360, ideal: 420, max: 520)
					}
			}
		}
		.task {
			shows.reach(console, library: library)
		}
		.onChange(of: console.link) {
			shows.reach(console, library: library)
		}
		.onChange(of: console.node) {
			shows.reach(console, library: library)
		}
		.onChange(of: scenePhase) {
			shows.settle(scenePhase)
		}
		.onChange(of: shows.refusal) {
			warn()
		}
	}
	
	private func warn() {
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
