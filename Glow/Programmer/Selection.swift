import SwiftData
import SwiftUI

@Observable @MainActor
final class Selection {
	private(set) var identifiers: Set<String> = []
	var isProgrammerOpen = false
	var isSceneOpen = false
	var section = "lights"
	var scene: String?
	var armed: [String: String] = [:]
	var aspects = Set(FeatureGroup.allCases)
	
	var building: String? {
		didSet {
			if building != oldValue { aspects = Set(FeatureGroup.allCases) }
		}
	}
	
	var isEmpty: Bool { identifiers.isEmpty }
	
	func contains(_ fixture: Fixture) -> Bool {
		identifiers.contains(fixture.identifier)
	}
	
	func contains(_ group: FixtureGroup) -> Bool {
		let members = Set(group.members.map(\.identifier))
		return !members.isEmpty && members.isSubset(of: identifiers)
	}
	
	func toggle(_ fixture: Fixture) {
		if identifiers.contains(fixture.identifier) {
			identifiers.remove(fixture.identifier)
		} else {
			identifiers.insert(fixture.identifier)
		}
		
		isProgrammerOpen = isProgrammerOpen && !isEmpty
	}
	
	func toggle(_ group: FixtureGroup) {
		let members = Set(group.members.map(\.identifier))
		if members.isSubset(of: identifiers) {
			identifiers.subtract(members)
		} else {
			identifiers.formUnion(members)
		}
		
		isProgrammerOpen = isProgrammerOpen && !isEmpty
	}
	
	func keep(_ patched: Set<String>) {
		guard !identifiers.isSubset(of: patched) else { return }
		identifiers.formIntersection(patched)
		isProgrammerOpen = isProgrammerOpen && !isEmpty
	}
	
	func arm(_ cue: String, of scene: String) {
		armed[scene] = armed[scene] == cue ? nil : cue
	}
	
	func clear() {
		identifiers.removeAll()
		isProgrammerOpen = false
	}
}
