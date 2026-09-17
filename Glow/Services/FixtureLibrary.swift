import Observation
import SwiftUI

@Observable @MainActor
final class FixtureLibrary {
    private(set) var bundled: [FixtureProfile] = []
    private(set) var custom: [FixtureProfile] = []

    var profiles: [FixtureProfile] { custom + bundled }

    init() {
        load()
    }

    private func load() {
        let decoder = JSONDecoder()
        let inFolder = Bundle.main.urls(forResourcesWithExtension: "json", subdirectory: "Profiles") ?? []
        let urls = inFolder.isEmpty
            ? Bundle.main.urls(forResourcesWithExtension: "json", subdirectory: nil) ?? []
            : inFolder

        bundled = urls
            .compactMap { url -> FixtureProfile? in
                guard let data = try? Data(contentsOf: url),
                      let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      object["channels"] is [Any]
                else { return nil }
                return try? decoder.decode(FixtureProfile.self, from: data)
            }
            .sorted { ($0.manufacturer, $0.model) < ($1.manufacturer, $1.model) }
    }

    func setCustom(_ profiles: [FixtureProfile]) {
        guard profiles != custom else { return }
        custom = profiles
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
