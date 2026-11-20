import SwiftData
import SwiftUI

@Model
final class Cue {
	var identifier: String = Identifier.fresh()
	var lookID: String = ""
	var sortIndex: Double = 0
	var label: String = ""
	var fade: Double = 0
	var delay: Double = 0
	var follow: Double?
	var values: Data = Data()
	
	init(lookID: String, sortIndex: Double, fade: Double, levels: Levels) {
		identifier = Identifier.fresh()
		self.lookID = lookID
		self.sortIndex = sortIndex
		self.fade = fade
		values = levels.data
	}
	
	var levels: Levels {
		get { Levels(values) ?? Levels() }
		set { values = newValue.data }
	}
	
	var entry: ShowContents.Cue {
		ShowContents.Cue(identifier: identifier, scene: lookID, sortIndex: sortIndex, label: label, fade: fade, delay: delay, follow: follow, levels: values)
	}
	
	func take(_ entry: ShowContents.Cue) {
		identifier = entry.identifier
		lookID = entry.scene
		sortIndex = entry.sortIndex
		label = entry.label
		fade = entry.fade
		delay = entry.delay
		follow = entry.follow
		values = entry.levels
	}
	
	func settleLabel() {
		let settled = label.trimmingCharacters(in: .whitespacesAndNewlines)
		if settled != label { label = settled }
	}
	
	@MainActor static func duplicate(_ chosen: [Cue], among held: [Cue], context: ModelContext) {
		let picked = Set(chosen.map(\.identifier))
		guard let last = held.lastIndex(where: { picked.contains($0.identifier) }) else { return }
		var ordered = held
		var copies: [Cue] = []
		
		for cue in held where picked.contains(cue.identifier) {
			var entry = cue.entry
			entry.identifier = Identifier.fresh()
			let copy = Cue(lookID: cue.lookID, sortIndex: cue.sortIndex, fade: cue.fade, levels: Levels())
			copy.take(entry)
			context.insert(copy)
			copies.append(copy)
		}
		
		ordered.insert(contentsOf: copies, at: last + 1)
		
		for (index, cue) in ordered.enumerated() where cue.sortIndex != Double(index + 1) {
			cue.sortIndex = Double(index + 1)
		}
	}
	
	@MainActor static func copy(_ chosen: [Cue], to look: Look, among cues: [Cue], context: ModelContext) {
		let start = (look.cues(among: cues).last?.sortIndex ?? 0).rounded(.down) + 1
		
		for (offset, cue) in chosen.enumerated() {
			var entry = cue.entry
			entry.identifier = Identifier.fresh()
			entry.scene = look.identifier
			entry.sortIndex = start + Double(offset)
			let copy = Cue(lookID: look.identifier, sortIndex: entry.sortIndex, fade: entry.fade, levels: Levels())
			copy.take(entry)
			context.insert(copy)
		}
	}
	
	@MainActor static func retime(_ chosen: [Cue], from start: CueDraft, to end: CueDraft) {
		for cue in chosen {
			if end.fade != start.fade { cue.fade = end.fade }
			if end.delay != start.delay { cue.delay = end.delay }
			if end.follow != start.follow { cue.follow = end.follow }
		}
	}
}
