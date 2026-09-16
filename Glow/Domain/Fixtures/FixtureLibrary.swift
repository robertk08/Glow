import Foundation
import Observation
import OSLog

/// The catalogue of fixture types the app knows about.
///
/// Profiles are bundled JSON rather than Swift, so a fixture that turns out to
/// disagree with its own manual is a data fix, and so the library can later be
/// extended by profiles the user writes or imports without any of this code
/// changing.
@Observable @MainActor final class FixtureLibrary {
    private(set) var profiles: [FixtureProfile] = []
    private(set) var loadFailures: [String] = []

    private let logger = Logger(subsystem: "com.robertkrause.Glow", category: "FixtureLibrary")

    func load() {
        var loaded: [FixtureProfile] = []
        var failures: [String] = []
        let decoder = JSONDecoder()
        let (urls, isFlattened) = Self.profileURLs()

        for url in urls {
            guard let data = try? Data(contentsOf: url) else { continue }

            // When the profiles land in the bundle root there is nothing in
            // the path to distinguish them from any other JSON the app might
            // ship, so anything without a channel list is simply not a
            // profile and is skipped rather than reported as broken.
            if isFlattened, !Self.looksLikeProfile(data) { continue }

            do {
                loaded.append(try decoder.decode(FixtureProfile.self, from: data))
            } catch {
                failures.append("\(url.lastPathComponent): \(error.localizedDescription)")
                logger.error("Profile \(url.lastPathComponent) failed to decode: \(error)")
            }
        }

        // The user's own fixture first, then alphabetically. Someone reaching
        // for the library is usually reaching for the light in front of them.
        profiles = loaded.sorted {
            if $0.isOwned != $1.isOwned { return $0.isOwned }
            if $0.manufacturer != $1.manufacturer { return $0.manufacturer < $1.manufacturer }
            return $0.model < $1.model
        }
        loadFailures = failures
    }

    /// A synchronized folder group copies loose resources into the bundle
    /// root rather than preserving the folder, so the subdirectory lookup is
    /// tried first and the root is the fallback. Both layouts work; which one
    /// you get depends on how the folder is added to the target, and that is
    /// not worth depending on.
    private static func profileURLs() -> (urls: [URL], isFlattened: Bool) {
        if let urls = Bundle.main.urls(forResourcesWithExtension: "json", subdirectory: "Profiles"),
           !urls.isEmpty {
            return (urls.sorted { $0.lastPathComponent < $1.lastPathComponent }, false)
        }
        let all = Bundle.main.urls(forResourcesWithExtension: "json", subdirectory: nil) ?? []
        return (all.sorted { $0.lastPathComponent < $1.lastPathComponent }, true)
    }

    private static func looksLikeProfile(_ data: Data) -> Bool {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return false
        }
        return object["channels"] is [Any] && object["id"] is String
    }

    func profile(id: String) -> FixtureProfile? {
        profiles.first { $0.id == id }
    }

    var manufacturers: [String] {
        Array(Set(profiles.map(\.manufacturer))).sorted()
    }

    func profiles(matching query: String) -> [FixtureProfile] {
        guard !query.trimmingCharacters(in: .whitespaces).isEmpty else { return profiles }
        return profiles.filter {
            $0.displayName.localizedCaseInsensitiveContains(query)
                || $0.mode.localizedCaseInsensitiveContains(query)
        }
    }
}
