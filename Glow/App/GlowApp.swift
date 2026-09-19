import SwiftData
import SwiftUI

@main
struct GlowApp: App {
	@State private var console = Console()
	@State private var library = FixtureLibrary()
	@State private var discovery = NodeDiscovery()
	@State private var shows = ShowLibrary()
	
	var body: some Scene {
		WindowGroup {
			RootView()
				.id(shows.activeID)
				.environment(console)
				.environment(library)
				.environment(discovery)
				.environment(shows)
				.task {
					console.start()
				}
		}
		.modelContainer(shows.container)
	}
}
