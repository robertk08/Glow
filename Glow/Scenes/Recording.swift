import Observation
import SwiftData
import SwiftUI

@Observable @MainActor
final class Recording: Identifiable {
	enum Destination {
		case scene
		case cue(Look)
		case into(Cue)
	}
	
	let destination: Destination
	let changed: Set<String>
	let selected: Set<String>
	var name: String
	var lights: Set<String>
	var features = Set(FeatureGroup.allCases)
	var keepsEverything: Bool
	var replaces = false
	var fade: Double
	
	private let console: Console
	private let fixtures: [Fixture]
	private let library: FixtureLibrary
	private let looks: [Look]
	private let cues: [Cue]
	
	init(_ destination: Destination, console: Console, fixtures: [Fixture], library: FixtureLibrary, looks: [Look], cues: [Cue]) {
		self.destination = destination
		self.console = console
		self.fixtures = fixtures
		self.library = library
		self.looks = looks
		self.cues = cues
		
		let everyone = Set(fixtures.map(\.identifier))
		changed = Set(fixtures.filter { fixture in fixture.range(library.type(fixture.typeID)).contains { DMXAddress($0).map(console.isActive) == true } }.map(\.identifier))
		selected = Set(fixtures.filter(console.selection.contains).map(\.identifier))
		
		switch destination {
		case .scene:
			name = Identifier.unusedName("Scene \(looks.count + 1)", among: looks.map(\.name))
			lights = selected.isEmpty ? everyone : selected
			keepsEverything = true
			fade = 0
		case let .cue(look):
			let held = look.cues(among: cues)
			name = ""
			lights = changed.isEmpty ? (selected.isEmpty ? everyone : selected) : changed
			keepsEverything = held.isEmpty
			fade = held.last?.fade ?? 0
		case let .into(cue):
			name = cue.name
			lights = changed.isEmpty ? selected : changed
			keepsEverything = false
			fade = cue.fade
		}
	}
	
	var title: String {
		switch destination {
		case .scene: "New Scene"
		case .cue: "New Cue"
		case let .into(cue): "Store into Cue \(cue.numberText)"
		}
	}
	
	var isScene: Bool {
		if case .scene = destination { return true }
		return false
	}
	
	var isInto: Bool {
		if case .into = destination { return true }
		return false
	}
	
	var isReady: Bool {
		!levels.isEmpty && (!isScene || !name.trimmingCharacters(in: .whitespaces).isEmpty)
	}
	
	var everyone: Set<String> {
		Set(fixtures.map(\.identifier))
	}
	
	var levels: Levels {
		var levels = Levels()
		
		for fixture in fixtures where lights.contains(fixture.identifier) {
			guard let type = library.type(fixture.typeID) else { continue }
			
			for channel in type.channels where features.contains(channel.attribute.group) {
				for offset in channel.offsets {
					guard let address = fixture.start.offset(by: offset - 1), keepsEverything || console.isActive(address) else { continue }
					levels.set(console.value(at: address), slot: offset, of: fixture.identifier)
				}
			}
		}
		
		return levels
	}
	
	func includes(_ members: [Fixture]) -> Bool {
		!members.isEmpty && members.allSatisfy { lights.contains($0.identifier) }
	}
	
	func toggle(_ members: [Fixture]) {
		let identifiers = Set(members.map(\.identifier))
		
		if includes(members) {
			lights.subtract(identifiers)
		} else {
			lights.formUnion(identifiers)
		}
	}
	
	func toggle(_ feature: FeatureGroup) {
		if features.contains(feature) {
			features.remove(feature)
		} else {
			features.insert(feature)
		}
	}
	
	func store(context: ModelContext) {
		let levels = levels
		let label = name.trimmingCharacters(in: .whitespaces)
		
		switch destination {
		case .scene:
			let look = Look(name: label, sortIndex: Console.nextSortIndex(looks, sortIndex: \.sortIndex))
			let cue = Cue(lookID: look.identifier, number: 1000, fade: fade, levels: levels)
			context.insert(look)
			context.insert(cue)
			try? context.save()
			console.arrive(at: cue.identifier)
		case let .cue(look):
			let held = look.cues(among: cues)
			let after = held.firstIndex { $0.identifier == console.activeCue } ?? held.count - 1
			let previous = held.indices.contains(after) ? held[after].number : nil
			let next = held.indices.contains(after + 1) ? held[after + 1].number : nil
			let number = Cue.number(after: previous, before: next) ?? Cue.number(after: held.last?.number, before: nil) ?? 1000
			let cue = Cue(lookID: look.identifier, number: number, fade: fade, levels: levels)
			cue.name = label
			context.insert(cue)
			try? context.save()
			console.arrive(at: cue.identifier)
		case let .into(cue):
			cue.levels = replaces ? levels : cue.levels.merging(levels)
			cue.name = label
			cue.fade = fade
		}
		
		for fixture in fixtures {
			guard let slots = levels.lights[fixture.identifier] else { continue }
			
			for slot in slots.keys {
				guard let address = fixture.start.offset(by: slot - 1) else { continue }
				console.release(address.value...address.value)
			}
		}
	}
}
