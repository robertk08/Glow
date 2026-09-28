import SwiftData
import SwiftUI

@Model
final class Look {
	var identifier: String = Identifier.fresh()
	var name: String = ""
	var sortIndex: Double = 0
	var symbolOverride: String?
	var tintName: String?
	var tapValue: Int = 0
	var buttonValues: [Int] = []
	
	init(name: String, sortIndex: Double) {
		identifier = Identifier.fresh()
		self.name = name
		self.sortIndex = sortIndex
	}
	
	var entry: ShowContents.Scene {
		ShowContents.Scene(identifier: identifier, name: name, sortIndex: sortIndex, symbol: symbolOverride, tint: tintName, tap: tap, buttons: buttons)
	}
	
	func take(_ entry: ShowContents.Scene) {
		identifier = entry.identifier
		name = entry.name
		sortIndex = entry.sortIndex
		symbolOverride = entry.symbol
		tintName = entry.tint
		tap = entry.tap
		buttons = entry.buttons
	}
	
	var isGone: Bool {
		isDeleted || modelContext == nil
	}
	
	var tap: SceneAction {
		get { SceneAction(rawValue: tapValue) ?? .toggle }
		set { tapValue = newValue.rawValue }
	}
	
	var buttons: [SceneAction] {
		get { buttonValues.compactMap(SceneAction.init(rawValue:)) }
		set { buttonValues = newValue.map(\.rawValue) }
	}
	
	func shows(_ button: SceneAction, _ isShown: Bool) {
		buttons = buttons.filter { $0 != button } + (isShown ? [button] : [])
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
	
	static func suggestedName(among looks: [Look]) -> String {
		Identifier.unusedName("Scene \(looks.count + 1)", among: looks.map(\.name))
	}
	
	@MainActor static func fresh(among looks: [Look], named name: String = "", context: ModelContext) -> Look {
		let name = name.trimmingCharacters(in: .whitespaces)
		let look = Look(name: name.isEmpty ? suggestedName(among: looks) : name, sortIndex: Console.nextSortIndex(looks, sortIndex: \.sortIndex))
		let tints = [FixtureTint.blue, .orange, .purple, .green, .pink, .yellow, .indigo, .red, .mint]
		look.tint = tints.min { first, second in looks.count { $0.tint == first } < looks.count { $0.tint == second } } ?? .blue
		context.insert(look)
		try? context.save()
		return look
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
		copy.tapValue = tapValue
		copy.buttonValues = buttonValues
		context.insert(copy)
		
		for cue in self.cues(among: cues) {
			var entry = cue.entry
			entry.identifier = Identifier.fresh()
			entry.scene = copy.identifier
			let twin = Cue(lookID: copy.identifier, sortIndex: entry.sortIndex, fade: entry.fade, levels: Levels())
			twin.take(entry)
			context.insert(twin)
		}
	}
}
