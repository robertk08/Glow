import SwiftData
import SwiftUI

@main
struct GlowApp: App {
    @State private var console = Console()
    @State private var library = FixtureLibrary()
    @State private var discovery = NodeDiscovery()

    var body: some Scene {
        WindowGroup {
            LightsView()
                .environment(console)
                .environment(library)
                .environment(discovery)
                .task { console.start() }
        }
        .modelContainer(for: Fixture.self)
    }
}
