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
	
	var belongsTo: [FixtureGroup] {
		(groups ?? []).sorted { $0.sortIndex < $1.sortIndex }
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
		var found: Set<PersistentIdentifier> = []
		
		for (index, fixture) in fixtures.enumerated() {
			let range = fixture.range(library.type(fixture.typeID))
			
			for other in fixtures.dropFirst(index + 1) where other.range(library.type(other.typeID)).overlaps(range) {
				found.insert(fixture.persistentModelID)
				found.insert(other.persistentModelID)
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
	
	static func unusedName(_ base: String, among fixtures: [Fixture]) -> String {
		let taken = Set(fixtures.map(\.name))
		guard taken.contains(base) else { return base }
		var index = 2
		
		while taken.contains("\(base) \(index)") {
			index += 1
		}
		
		return "\(base) \(index)"
	}
}
