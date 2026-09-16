import Observation
import SwiftUI

@Observable @MainActor
final class FixtureLibrary {
    private(set) var profiles: [FixtureProfile] = []

    func load() {
        let decoder = JSONDecoder()
        let urls = Bundle.main.urls(forResourcesWithExtension: "json", subdirectory: "Profiles")
            ?? Bundle.main.urls(forResourcesWithExtension: "json", subdirectory: nil)
            ?? []

        profiles = urls
            .compactMap { url -> FixtureProfile? in
                guard let data = try? Data(contentsOf: url),
                      let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      object["channels"] is [Any]
                else { return nil }
                return try? decoder.decode(FixtureProfile.self, from: data)
            }
            .sorted { ($0.manufacturer, $0.model) < ($1.manufacturer, $1.model) }
    }

    func profile(_ id: String) -> FixtureProfile? {
        profiles.first { $0.id == id }
    }

    func search(_ query: String) -> [FixtureProfile] {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return profiles }
        return profiles.filter {
            $0.name.localizedCaseInsensitiveContains(trimmed)
                || $0.mode.localizedCaseInsensitiveContains(trimmed)
        }
    }
}
