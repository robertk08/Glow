import SwiftData
import SwiftUI

@Model
final class Look {
	var identifier: String = Identifier.fresh()
	var name: String = ""
	var sortIndex: Double = 0
	var loops: Bool = false
	
	init(name: String, sortIndex: Double) {
		identifier = Identifier.fresh()
		self.name = name
		self.sortIndex = sortIndex
	}
	
	var entry: ShowContents.Scene {
		ShowContents.Scene(identifier: identifier, name: name, sortIndex: sortIndex, loops: loops)
	}
	
	func take(_ entry: ShowContents.Scene) {
		identifier = entry.identifier
		name = entry.name
		sortIndex = entry.sortIndex
		loops = entry.loops
	}
	
	func cues(among cues: [Cue]) -> [Cue] {
		cues.filter { $0.lookID == identifier }.sorted { ($0.number, $0.identifier) < ($1.number, $1.identifier) }
	}
	
	func remove(with cues: [Cue], context: ModelContext) {
		for cue in self.cues(among: cues) {
			context.delete(cue)
		}
		
		context.delete(self)
	}
	
	@MainActor func duplicate(with cues: [Cue], among looks: [Look], context: ModelContext) {
		let copy = Look(name: Identifier.unusedName(name, among: looks.map(\.name)), sortIndex: Console.nextSortIndex(looks, sortIndex: \.sortIndex))
		copy.loops = loops
		context.insert(copy)
		
		for cue in self.cues(among: cues) {
			var entry = cue.entry
			entry.identifier = Identifier.fresh()
			entry.scene = copy.identifier
			let twin = Cue(lookID: copy.identifier, number: entry.number, fade: entry.fade, levels: Levels())
			twin.take(entry)
			context.insert(twin)
		}
	}
}
