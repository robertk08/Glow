import Observation
import SwiftData
import SwiftUI

@Observable @MainActor
final class Recording: Identifiable {
	enum Destination {
		case scene
		case cue(Look, after: Cue?)
		case into(Cue)
	}
	
	let destination: Destination
	var label: String
	var lights: Set<String>
	var features = Set(FeatureGroup.allCases)
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
		let selected = Set(fixtures.filter(console.selection.contains).map(\.identifier))
		let changed = Set(fixtures.filter { fixture in fixture.range(library.type(fixture.typeID)).contains { DMXAddress($0).map(console.isActive) == true } }.map(\.identifier))
		lights = selected.isEmpty ? (changed.isEmpty ? everyone : changed) : selected
		
		switch destination {
		case .scene:
			label = Identifier.unusedName("Scene \(looks.count + 1)", among: looks.map(\.name))
			fade = 0
		case let .cue(look, _):
			label = ""
			fade = look.cues(among: cues).last?.fade ?? 0
		case let .into(cue):
			label = cue.label
			fade = cue.fade
			let held = everyone.intersection(cue.levels.lights.keys)
			if selected.isEmpty, changed.isEmpty, !held.isEmpty { lights = held }
		}
	}
	
	var title: String {
		switch destination {
		case .scene: "New Scene"
		case .cue: "New Cue"
		case .into: "Store into Cue"
		}
	}
	
	var isScene: Bool {
		if case .scene = destination { return true }
		return false
	}
	
	var isReady: Bool {
		!levels.isEmpty && (!isScene || !label.trimmingCharacters(in: .whitespaces).isEmpty)
	}
	
	var summary: String {
		let count = levels.lights.count
		guard count > 0 else { return "Choose at least one light and one aspect." }
		let lights = count == 1 ? "1 light" : "\(count) lights"
		guard features.count < FeatureGroup.allCases.count else { return "Stores everything \(lights) \(count == 1 ? "is" : "are") doing." }
		return "Stores \(FeatureGroup.allCases.filter(features.contains).map(\.name).formatted(.list(type: .and)).lowercased()) of \(lights)."
	}
	
	var levels: Levels {
		var levels = Levels()
		
		for fixture in fixtures where lights.contains(fixture.identifier) {
			guard let type = library.type(fixture.typeID) else { continue }
			
			for channel in type.channels where features.contains(channel.attribute.group) {
				for offset in channel.offsets {
					guard let address = fixture.start.offset(by: offset - 1) else { continue }
					levels.set(console.value(at: address), slot: offset, of: fixture.identifier)
				}
			}
		}
		
		return levels
	}
	
	func toggle(_ fixture: Fixture) {
		if lights.contains(fixture.identifier) {
			lights.remove(fixture.identifier)
		} else {
			lights.insert(fixture.identifier)
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
		let label = label.trimmingCharacters(in: .whitespaces)
		
		switch destination {
		case .scene:
			let look = Look(name: label, sortIndex: Console.nextSortIndex(looks, sortIndex: \.sortIndex))
			context.insert(look)
			context.insert(Cue(lookID: look.identifier, sortIndex: 1, fade: fade, levels: levels))
		case let .cue(look, after):
			let held = look.cues(among: cues)
			var sortIndex = Console.nextSortIndex(held, sortIndex: \.sortIndex)
			
			if let after, let position = held.firstIndex(where: { $0.identifier == after.identifier }), held.indices.contains(position + 1) {
				sortIndex = (held[position].sortIndex + held[position + 1].sortIndex) / 2
			}
			
			let cue = Cue(lookID: look.identifier, sortIndex: sortIndex, fade: fade, levels: levels)
			cue.label = label
			context.insert(cue)
		case let .into(cue):
			cue.levels = cue.levels.merging(levels)
			cue.label = label
			cue.fade = fade
		}
		
		try? context.save()
		
		for fixture in fixtures {
			guard let slots = levels.lights[fixture.identifier] else { continue }
			
			for slot in slots.keys {
				guard let address = fixture.start.offset(by: slot - 1) else { continue }
				console.release(address.value...address.value)
			}
		}
	}
}
