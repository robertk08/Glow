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
	
	var draft: CueDraft {
		didSet {
			if isNew { console.selection.draft = draft }
		}
	}
	
	private let chosen: Set<String>
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
		
		switch destination {
		case .cue:
			draft = console.selection.draft
			chosen = selected.isEmpty ? Set(fixtures.map(\.identifier)) : selected
		case .into:
			draft = CueDraft()
			chosen = selected.isEmpty ? Set(fixtures.filter { $0.range(library.type($0.typeID)).contains(where: console.active.contains) }.map(\.identifier)) : selected
		}
	}
	
	var label: String {
		get { draft.label }
		set { draft.label = newValue }
	}
	
	var fade: Double {
		get { draft.fade }
		set { draft.fade = newValue }
	}
	
	var delay: Double {
		get { draft.delay }
		set { draft.delay = newValue }
	}
	
	var follow: Double? {
		get { draft.follow }
		set { draft.follow = newValue }
	}
	
	var features: Set<FeatureGroup> {
		get { draft.aspects }
		set { draft.aspects = newValue }
	}
	
	var lights: Set<String> {
		get { draft.lights ?? chosen }
		set { draft.lights = newValue }
	}
	
	var isNew: Bool {
		guard case .cue = destination else { return false }
		return true
	}
	
	var title: String {
		switch destination {
		case .cue: "Cue \(number)"
		case .into: "Update Cue \(number)"
		}
	}
	
	var number: Int {
		switch destination {
		case let .cue(look, after):
			let held = look.cues(among: cues)
			guard let after, let position = held.firstIndex(where: { $0.identifier == after.identifier }) else { return held.count + 1 }
			return position + 2
		case let .into(cue):
			let held = looks.first { $0.identifier == cue.lookID }?.cues(among: cues) ?? []
			return (held.firstIndex { $0.identifier == cue.identifier } ?? 0) + 1
		}
	}
	
	var slot: Double {
		switch destination {
		case let .cue(look, after):
			let held = look.cues(among: cues)
			let last = (held.last?.sortIndex ?? 0).rounded(.down) + 1
			guard let after, let position = held.firstIndex(where: { $0.identifier == after.identifier }), held.indices.contains(position + 1) else { return last }
			return Console.sortIndex(between: held[position].sortIndex, and: held[position + 1].sortIndex) ?? held[position].sortIndex + 1
		case let .into(cue): return cue.sortIndex
		}
	}
	
	var hint: String {
		var parts = [lights.count >= fixtures.count ? "All lights" : lights.count == 1 ? "1 light" : "\(lights.count) lights"]
		if fade > 0 { parts.append(CueList.seconds(fade)) }
		if delay > 0 { parts.append("Wait \(CueList.seconds(delay))") }
		if follow != nil { parts.append("Auto") }
		return parts.joined(separator: " · ")
	}
	
	var isReady: Bool {
		!levels.isEmpty
	}
	
	var levels: Levels {
		var levels = Levels()
		
		for fixture in fixtures where lights.contains(fixture.identifier) {
			guard let type = library.type(fixture.typeID) else { continue }
			
			let stored = features.flatMap(type.channels(storedWith:))
			
			for channel in type.channels where stored.contains(channel) {
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
	
	func contains(_ group: FixtureGroup) -> Bool {
		let members = Set(group.members.map(\.identifier))
		return !members.isEmpty && members.isSubset(of: lights)
	}
	
	func toggle(_ group: FixtureGroup) {
		let members = Set(group.members.map(\.identifier))
		
		if members.isSubset(of: lights) {
			lights.subtract(members)
		} else {
			lights.formUnion(members)
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
			let sortIndex = slot
			
			if let after, let position = held.firstIndex(where: { $0.identifier == after.identifier }), held.indices.contains(position + 1), sortIndex >= held[position + 1].sortIndex {
				for (offset, later) in held[(position + 1)...].enumerated() {
					later.sortIndex = sortIndex + 1 + Double(offset)
				}
			}
			
			let cue = Cue(lookID: look.identifier, sortIndex: sortIndex, fade: fade, levels: levels)
			cue.label = label
			cue.delay = delay
			cue.follow = follow
			context.insert(cue)
			landing = (cue.identifier, look)
			console.selection.marked = cue.identifier
			draft.label = ""
			
			if held.count == 1, look.tap == .toggle, look.buttons.isEmpty {
				look.tap = .next
				look.buttons = [.back, .toggle]
			}
		case let .into(cue):
			cue.levels = cue.levels.merging(levels)
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
