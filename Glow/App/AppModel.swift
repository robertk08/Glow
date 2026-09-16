import Foundation
import Observation
import SwiftData

/// Everything with a lifetime longer than a screen.
@Observable @MainActor final class AppModel {
    let library = FixtureLibrary()
    let engine = ConsoleEngine()
    let discovery = NodeDiscovery()

    /// The node we connect to on launch. Remembered across launches so the app
    /// is useful the moment it opens rather than after a trip to Settings.
    var endpoint: ControllerEndpoint {
        didSet {
            Self.persist(endpoint)
            engine.connect(to: endpoint)
        }
    }

    private static let endpointKey = "controller.endpoint"

    init() {
        endpoint = Self.restored() ?? .defaultNode

        // Loaded here rather than in bootstrap() because the patch is read the
        // moment the first view appears, and a patch resolved against an empty
        // library silently produces a rig with no dimmers in it.
        library.load()
    }

    func bootstrap() {
        engine.start()
        engine.connect(to: endpoint)
        discovery.start()
    }

    /// Keeps the output stage's idea of how each fixture dims in step with
    /// the patch. Called whenever the patch changes.
    func patchDidChange(_ fixtures: [PatchedFixture]) {
        engine.setIntensityScalers(fixtures.flatMap { control(for: $0)?.intensityScalers ?? [] })
    }

    func profile(for fixture: PatchedFixture) -> FixtureProfile? {
        library.profile(id: fixture.profileID)
    }

    func control(for fixture: PatchedFixture) -> FixtureControl? {
        guard let profile = profile(for: fixture) else { return nil }
        return FixtureControl(
            profile: profile,
            startAddress: fixture.startAddress,
            engine: engine
        )
    }

    private static func restored() -> ControllerEndpoint? {
        guard let data = UserDefaults.standard.data(forKey: endpointKey) else { return nil }
        return try? JSONDecoder().decode(ControllerEndpoint.self, from: data)
    }

    private static func persist(_ endpoint: ControllerEndpoint) {
        guard let data = try? JSONEncoder().encode(endpoint) else { return }
        UserDefaults.standard.set(data, forKey: endpointKey)
    }
}
