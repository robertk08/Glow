import SwiftData
import SwiftUI

@main
struct GlowApp: App {
    @State private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
                .task { model.bootstrap() }
        }
        .modelContainer(for: PatchedFixture.self)
    }
}
