import Observation
import SwiftUI

@Observable @MainActor
final class FixtureLibrary {
	private(set) var bundled: [FixtureProfile] = []
	private(set) var custom: [FixtureProfile] = []
	private(set) var profiles: [FixtureProfile] = []
	
	private var byIdentifier: [String: FixtureProfile] = [:]
	
	init() {
		let decoder = JSONDecoder()
		
		bundled = (Bundle.main.urls(forResourcesWithExtension: "json", subdirectory: nil) ?? [])
			.compactMap { url in
				guard let data = try? Data(contentsOf: url) else { return nil }
				return try? decoder.decode(FixtureProfile.self, from: data)
			}
			.sorted { first, second in
				if first.manufacturer.isEmpty != second.manufacturer.isEmpty {
					return second.manufacturer.isEmpty
				}
				return (first.manufacturer, first.model, first.channelCount) < (second.manufacturer, second.model, second.channelCount)
			}
		
		index()
	}
	
	func setCustom(_ profiles: [FixtureProfile]) {
		guard profiles != custom else { return }
		custom = profiles
		index()
	}
	
	func profile(_ id: String) -> FixtureProfile? {
		byIdentifier[id]
	}
	
	func search(_ query: String) -> [FixtureProfile] {
		let trimmed = query.trimmingCharacters(in: .whitespaces)
		guard !trimmed.isEmpty else { return profiles }
		return profiles.filter {
			$0.name.localizedCaseInsensitiveContains(trimmed)
				|| $0.mode.localizedCaseInsensitiveContains(trimmed)
		}
	}
	
	func patched(_ identifier: String?, among fixtures: [Fixture]) -> [String] {
		guard let identifier else { return [] }
		return fixtures.filter { profile($0.profileID)?.id == identifier }.map(\.name)
	}
	
	func channelsUsed(by fixtures: [Fixture]) -> Int {
		fixtures.reduce(0) { $0 + (profile($1.profileID)?.channelCount ?? 0) }
	}
	
	private func index() {
		profiles = custom + bundled
		byIdentifier = Dictionary(profiles.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
	}
}
