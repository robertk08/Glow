import SwiftData
import SwiftUI

@main
struct GlowApp: App {
	@State private var console = Console()
	@State private var library = FixtureLibrary()
	@State private var shows = ShowLibrary()
	
	var body: some Scene {
		WindowGroup {
			RootView()
				.environment(console)
				.environment(library)
				.environment(shows)
				.task {
					console.start()
				}
		}
		.modelContainer(shows.container)
	}
}
