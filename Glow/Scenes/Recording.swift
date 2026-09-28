import Observation
import SwiftData
import SwiftUI

@Observable @MainActor
final class Recording: Identifiable {
	enum Destination {
		case cue(Look, after: Cue?)
		case into(Cue)
	}
	
	let destination: Destination
	let selected: Set<String>
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
		
		selected = Set(fixtures.filter(console.selection.contains).map(\.identifier))
		lights = selected.isEmpty ? Set(fixtures.map(\.identifier)) : selected
		
		switch destination {
		case let .cue(look, _):
			label = ""
			fade = look.cues(among: cues).last?.fade ?? 0
		case let .into(cue):
			label = cue.label
			fade = cue.fade
		}
	}
	
	var title: String {
		switch destination {
		case .cue: "Cue \(number)"
		case .into: "Store into Cue"
		}
	}
	
	var number: Int {
		guard case let .cue(look, after) = destination else { return 0 }
		let held = look.cues(among: cues)
		guard let after, let position = held.firstIndex(where: { $0.identifier == after.identifier }) else { return held.count + 1 }
		return position + 2
	}
	
	var hint: String {
		guard !selected.isEmpty else { return "All lights" }
		return selected.count == 1 ? "1 light" : "\(selected.count) lights"
	}
	
	var isReady: Bool {
		!levels.isEmpty
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
		var landing: (cue: String, look: Look)?
		
		switch destination {
		case let .cue(look, after):
			let held = look.cues(among: cues)
			var sortIndex = Console.nextSortIndex(held, sortIndex: \.sortIndex)
			
			if let after, let position = held.firstIndex(where: { $0.identifier == after.identifier }), held.indices.contains(position + 1) {
				sortIndex = Console.sortIndex(between: held[position].sortIndex, and: held[position + 1].sortIndex) ?? held[position].sortIndex + 1
				
				if sortIndex > held[position + 1].sortIndex {
					for (offset, later) in held[(position + 1)...].enumerated() {
						later.sortIndex = sortIndex + 1 + Double(offset)
					}
				}
			}
			
			let cue = Cue(lookID: look.identifier, sortIndex: sortIndex, fade: fade, levels: levels)
			cue.label = label
			context.insert(cue)
			landing = (cue.identifier, look)
			
			if held.count == 1, look.tap == .toggle, look.buttons.isEmpty {
				look.tap = .next
				look.buttons = [.back, .toggle]
			}
		case let .into(cue):
			cue.levels = cue.levels.merging(levels)
			cue.label = label
			cue.fade = fade
			if console.playback.cue(of: cue.lookID) == cue.identifier, let look = looks.first(where: { $0.identifier == cue.lookID }) { landing = (cue.identifier, look) }
		}
		
		try? context.save()
		
		for fixture in fixtures {
			guard let slots = levels.lights[fixture.identifier] else { continue }
			
			for slot in slots.keys {
				guard let address = fixture.start.offset(by: slot - 1) else { continue }
				console.release(address.value...address.value)
			}
		}
		
		guard let landing else { return }
		let list = CueList(landing.look, cues: (try? context.fetch(FetchDescriptor<Cue>())) ?? [], fixtures: fixtures)
		guard let index = list.index(of: landing.cue) else { return }
		console.land(list, at: index)
	}
}
