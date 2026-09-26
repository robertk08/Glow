import Observation
import SwiftData
import SwiftUI

@Observable @MainActor
final class FixtureLibrary {
	private(set) var builtIn: [FixtureType] = []
	private(set) var made: [FixtureType] = []
	private(set) var types: [FixtureType] = []
	
	private var byIdentifier: [String: FixtureType] = [:]
	
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
				return (first.manufacturer, first.model, first.channelCount) < (second.manufacturer, second.model, second.channelCount)
			}
	}
	
	func setMade(_ types: [FixtureType]) {
		guard types != made else { return }
		made = types
		index()
	}
	
	func type(_ id: String) -> FixtureType? {
		byIdentifier[id]
	}
	
	func search(_ query: String) -> [FixtureType] {
		let trimmed = query.trimmingCharacters(in: .whitespaces)
		guard !trimmed.isEmpty else { return types }
		return types.filter {
			$0.name.localizedCaseInsensitiveContains(trimmed) || $0.mode.localizedCaseInsensitiveContains(trimmed)
		}
	}
	
	func patched(_ id: String?, among fixtures: [Fixture]) -> [String] {
		guard let id else { return [] }
		return fixtures.filter { $0.typeID == id }.map(\.name)
	}
	
	func channelsUsed(by fixtures: [Fixture]) -> Int {
		fixtures.reduce(0) { $0 + (type($1.typeID)?.channelCount ?? 0) }
	}
	
	func isNameTaken(_ draft: FixtureType) -> Bool {
		var candidate = draft
		candidate.manufacturer = draft.manufacturer.trimmingCharacters(in: .whitespaces)
		candidate.model = draft.model.trimmingCharacters(in: .whitespaces)
		let editsItself = made.contains { $0.id == draft.id }
		
		return types.contains { type in
			!(editsItself && type.id == draft.id) && type.name.caseInsensitiveCompare(candidate.name) == .orderedSame
		}
	}
	
	func unusedIdentifier(_ base: String) -> String {
		var cleaned = ""
		
		for character in base.lowercased() {
			if character.isASCII, character.isLetter || character.isNumber {
				cleaned.append(character)
			} else if !cleaned.isEmpty, !cleaned.hasSuffix("-") {
				cleaned.append("-")
			}
		}
		
		cleaned = String(cleaned.prefix(32))
		
		while cleaned.hasSuffix("-") {
			cleaned.removeLast()
		}
		
		if cleaned.isEmpty {
			cleaned = "made"
		}
		
		var candidate = cleaned
		var index = 2
		
		while types.contains(where: { $0.id == candidate }) {
			candidate = "\(cleaned)-\(index)"
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
		
		if let existing {
			existing.definition = saved
		} else {
			context.insert(StoredFixtureType(saved))
		}
		
		guard let original, original.id != saved.id else { return }
		
		for fixture in fixtures where fixture.typeID == original.id {
			fixture.typeID = saved.id
		}
	}
	
	private func index() {
		types = made + builtIn
		byIdentifier = Dictionary(types.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
	}
}
