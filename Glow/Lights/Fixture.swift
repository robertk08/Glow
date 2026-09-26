import SwiftData
import SwiftUI

@Model
final class Fixture {
	var identifier: String = Identifier.fresh()
	var typeID: String = ""
	var name: String = ""
	var address: Int = 1
	var sortIndex: Double = 0
	var symbolOverride: String?
	var invertsPan: Bool = false
	var invertsTilt: Bool = false
	var groups: [FixtureGroup]? = []
	
	init(typeID: String, name: String, address: DMXAddress, sortIndex: Double) {
		identifier = Identifier.fresh()
		self.typeID = typeID
		self.name = name
		self.address = address.value
		self.sortIndex = sortIndex
	}
	
	var entry: ShowContents.Light {
		ShowContents.Light(identifier: identifier, typeID: typeID, name: name, address: address, sortIndex: sortIndex, symbol: symbolOverride, groups: (groups ?? []).map(\.identifier).sorted(), invertsPan: invertsPan, invertsTilt: invertsTilt)
	}
	
	func take(_ entry: ShowContents.Light, groups: [FixtureGroup]) {
		identifier = entry.identifier
		typeID = entry.typeID
		name = entry.name
		address = entry.address
		sortIndex = entry.sortIndex
		symbolOverride = entry.symbol
		invertsPan = entry.invertsPan
		invertsTilt = entry.invertsTilt
		
		for group in groups {
			belong(to: group, entry.groups.contains(group.identifier))
		}
	}
	
	func belongs(to group: FixtureGroup) -> Bool {
		(groups ?? []).contains { $0.identifier == group.identifier }
	}
	
	func belong(to group: FixtureGroup, _ isMember: Bool) {
		if isMember {
			guard !belongs(to: group) else { return }
			groups = (groups ?? []) + [group]
		} else {
			groups?.removeAll { $0.identifier == group.identifier }
		}
	}
	
	var start: DMXAddress {
		get { DMXAddress(clamping: address) }
		set { address = newValue.value }
	}
	
	func symbol(_ mode: FixtureType?) -> String {
		symbolOverride ?? mode?.symbol ?? "lightbulb"
	}
	
	func range(_ mode: FixtureType?) -> ClosedRange<Int> {
		address...(address + max(1, mode?.channelCount ?? 1) - 1)
	}
	
	@MainActor static func clashing(among fixtures: [Fixture], library: FixtureLibrary) -> Set<PersistentIdentifier> {
		let spans = fixtures.map { ($0.persistentModelID, $0.range(library.type($0.typeID))) }.sorted { $0.1.lowerBound < $1.1.lowerBound }
		var found: Set<PersistentIdentifier> = []
		var widest: (id: PersistentIdentifier, reach: Int)?
		
		for (id, span) in spans {
			if let widest, span.lowerBound <= widest.reach {
				found.insert(id)
				found.insert(widest.id)
			}
			
			if span.upperBound > widest?.reach ?? 0 {
				widest = (id, span.upperBound)
			}
		}
		
		return found
	}
	
	@MainActor static func overlapping(_ fixture: Fixture, among fixtures: [Fixture], library: FixtureLibrary) -> [Fixture] {
		let span = fixture.range(library.type(fixture.typeID))
		return fixtures.filter { $0.persistentModelID != fixture.persistentModelID && $0.range(library.type($0.typeID)).overlaps(span) }
	}
	
	@MainActor static func firstFreeAddress(width: Int, among fixtures: [Fixture], library: FixtureLibrary) -> Int {
		var candidate = 1
		
		for range in fixtures.map({ $0.range(library.type($0.typeID)) }).sorted(by: { $0.lowerBound < $1.lowerBound }) {
			if candidate + width - 1 < range.lowerBound { break }
			candidate = max(candidate, range.upperBound + 1)
		}
		
		return min(candidate, Universe.channelCount)
	}
}
