import SwiftData
import SwiftUI

@Observable @MainActor
final class Selection {
	private(set) var identifiers: Set<PersistentIdentifier> = []
	var isProgrammerOpen = false
	
	var isEmpty: Bool { identifiers.isEmpty }
	
	func contains(_ fixture: Fixture) -> Bool {
		identifiers.contains(fixture.persistentModelID)
	}
	
	func contains(_ group: FixtureGroup) -> Bool {
		let members = Set(group.members.map(\.persistentModelID))
		return !members.isEmpty && members.isSubset(of: identifiers)
	}
	
	func toggle(_ fixture: Fixture) {
		if identifiers.contains(fixture.persistentModelID) {
			identifiers.remove(fixture.persistentModelID)
		} else {
			identifiers.insert(fixture.persistentModelID)
		}
		
		isProgrammerOpen = isProgrammerOpen && !isEmpty
	}
	
	func toggle(_ group: FixtureGroup) {
		let members = Set(group.members.map(\.persistentModelID))
		if members.isSubset(of: identifiers) {
			identifiers.subtract(members)
		} else {
			identifiers.formUnion(members)
		}
		
		isProgrammerOpen = isProgrammerOpen && !isEmpty
	}
	
	func forget(_ fixture: Fixture) {
		identifiers.remove(fixture.persistentModelID)
		isProgrammerOpen = isProgrammerOpen && !isEmpty
	}
	
	func clear() {
		identifiers.removeAll()
		isProgrammerOpen = false
	}
}
