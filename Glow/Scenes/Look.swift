import SwiftData
import SwiftUI

@Model
final class Look {
	var identifier: String = Identifier.fresh()
	var name: String = ""
	var sortIndex: Double = 0
	var symbolOverride: String?
	var tintName: String?
	
	init(name: String, sortIndex: Double) {
		identifier = Identifier.fresh()
		self.name = name
		self.sortIndex = sortIndex
	}
	
	var entry: ShowContents.Scene {
		ShowContents.Scene(identifier: identifier, name: name, sortIndex: sortIndex, symbol: symbolOverride, tint: tintName)
	}
	
	func take(_ entry: ShowContents.Scene) {
		identifier = entry.identifier
		name = entry.name
		sortIndex = entry.sortIndex
		symbolOverride = entry.symbol
		tintName = entry.tint
	}
	
	var tint: FixtureTint {
		get { tintName.flatMap(FixtureTint.init(rawValue:)) ?? .none }
		set { tintName = newValue == .none ? nil : newValue.rawValue }
	}
	
	var symbol: String {
		symbolOverride ?? "theatermasks"
	}
	
	func cues(among cues: [Cue]) -> [Cue] {
		cues.filter { $0.lookID == identifier }.sorted { ($0.sortIndex, $0.identifier) < ($1.sortIndex, $1.identifier) }
	}
	
	func remove(with cues: [Cue], context: ModelContext) {
		for cue in self.cues(among: cues) {
			context.delete(cue)
		}
		
		context.delete(self)
	}
	
	@MainActor func duplicate(with cues: [Cue], among looks: [Look], context: ModelContext) {
		let copy = Look(name: Identifier.unusedName(name, among: looks.map(\.name)), sortIndex: Console.nextSortIndex(looks, sortIndex: \.sortIndex))
		copy.symbolOverride = symbolOverride
		copy.tintName = tintName
		context.insert(copy)
		
		for cue in self.cues(among: cues) {
			let twin = Cue(lookID: copy.identifier, sortIndex: cue.sortIndex, fade: cue.fade, levels: cue.levels)
			twin.label = cue.label
			context.insert(twin)
		}
	}
}
