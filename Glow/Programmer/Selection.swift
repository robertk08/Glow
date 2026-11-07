import SwiftData
import SwiftUI

@Observable
final class Selection {
	enum Section {
		case lights
		case scenes
		case settings
	}
	
	private(set) var identifiers: Set<String> = []
	
	var isProgrammerOpen = false
	var isSceneOpen = false
	var section = Section.lights
	var scene: String?
	var draft = CueDraft()
	var seed = CueDraft()
	var marked: String?
	var isNew = false
	var kept: (scene: ShowContents.Scene, cues: [ShowContents.Cue], playing: String?)?
	
	var building: String? {
		didSet {
			guard building != oldValue else { return }
			draft = CueDraft()
			seed = CueDraft()
			marked = nil
			kept = nil
			isNew = false
		}
	}
	
	var isEmpty: Bool { identifiers.isEmpty }
	
	func build(_ scene: String, isNew: Bool = false) {
		guard building == nil else {
			section = .lights
			return
		}
		
		building = scene
		self.isNew = isNew
	}
	
	func open(scene: String, isSheet: Bool) {
		self.scene = scene
		isSceneOpen = isSheet
	}
	
	func follow(_ started: String, isIdle: Bool) {
		guard isIdle, !isSceneOpen, scene != started else { return }
		scene = nil
	}
	
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
	
	func clear() {
		identifiers.removeAll()
		isProgrammerOpen = false
	}
}
