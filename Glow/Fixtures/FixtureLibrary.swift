import Observation
import SwiftData
import SwiftUI

@Observable @MainActor
final class FixtureLibrary {
	private(set) var builtIn: [FixtureType] = []
	private(set) var made: [FixtureType] = []
	private(set) var types: [FixtureType] = []
	private(set) var modes: [FixtureMode] = []
	
	private var byIdentifier: [String: FixtureMode] = [:]
	
	init(builtIn: [FixtureType] = FixtureLibrary.bundled()) {
		self.builtIn = builtIn
		index()
	}
	
	static func bundled() -> [FixtureType] {
		let decoder = JSONDecoder()
		
		return (Bundle.main.urls(forResourcesWithExtension: "json", subdirectory: nil) ?? [])
			.compactMap { url in
				guard let data = try? Data(contentsOf: url) else { return nil }
				return try? decoder.decode(FixtureType.self, from: data)
			}
			.sorted { first, second in
				if first.manufacturer.isEmpty != second.manufacturer.isEmpty {
					return second.manufacturer.isEmpty
				}
				return (first.manufacturer, first.model) < (second.manufacturer, second.model)
			}
	}
	
	func setMade(_ types: [FixtureType]) {
		guard types != made else { return }
		made = types
		index()
	}
	
	func mode(_ id: String) -> FixtureMode? {
		byIdentifier[id]
	}
	
	func type(_ id: String) -> FixtureType? {
		types.first { $0.id == id }
	}
	
	func type(holding modeID: String) -> FixtureType? {
		types.first { type in type.fixtureModes.contains { $0.id == modeID } }
	}
	
	func search(_ query: String) -> [FixtureType] {
		let trimmed = query.trimmingCharacters(in: .whitespaces)
		guard !trimmed.isEmpty else { return types }
		return types.filter { type in
			type.name.localizedCaseInsensitiveContains(trimmed)
				|| type.modes.contains { $0.name.localizedCaseInsensitiveContains(trimmed) }
		}
	}
	
	func patched(_ typeID: String?, among fixtures: [Fixture]) -> [String] {
		guard let typeID else { return [] }
		return fixtures.filter { mode($0.typeID)?.typeID == typeID }.map(\.name)
	}
	
	func channelsUsed(by fixtures: [Fixture]) -> Int {
		fixtures.reduce(0) { $0 + (mode($1.typeID)?.channelCount ?? 0) }
	}
	
	func unusedIdentifier(_ base: String) -> String {
		var candidate = base
		var index = 2
		
		while types.contains(where: { $0.id == candidate }) {
			candidate = "\(base)-\(index)"
			index += 1
		}
		
		return candidate
	}
	
	func adopt(_ draft: FixtureType, replacing original: FixtureType?, among fixtures: [Fixture], stored: [StoredFixtureType], context: ModelContext) {
		var saved = draft
		let existing = stored.first { $0.identifier == draft.id }
		
		if existing == nil {
			saved.id = unusedIdentifier(draft.id.isEmpty || builtIn.contains { $0.id == draft.id } ? "\(draft.model.lowercased().replacingOccurrences(of: " ", with: "-"))-made" : draft.id)
		}
		
		var moves: [String: String] = [:]
		
		if let original {
			for (index, mode) in original.modes.enumerated() where index < saved.modes.count {
				moves[original.identifier(of: mode)] = saved.identifier(of: saved.modes[index])
			}
		}
		
		if let existing {
			existing.definition = saved
		} else {
			context.insert(StoredFixtureType(saved))
		}
		
		for fixture in fixtures {
			guard let moved = moves[fixture.typeID], moved != fixture.typeID else { continue }
			fixture.typeID = moved
		}
	}
	
	private func index() {
		types = made + builtIn
		modes = types.flatMap(\.fixtureModes)
		byIdentifier = Dictionary(modes.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
	}
}
