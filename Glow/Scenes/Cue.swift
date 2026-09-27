import SwiftData
import SwiftUI

@Model
final class Cue {
	var identifier: String = Identifier.fresh()
	var lookID: String = ""
	var sortIndex: Double = 0
	var label: String = ""
	var fade: Double = 0
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
		ShowContents.Cue(identifier: identifier, scene: lookID, sortIndex: sortIndex, label: label, fade: fade, levels: values)
	}
	
	func take(_ entry: ShowContents.Cue) {
		identifier = entry.identifier
		lookID = entry.scene
		sortIndex = entry.sortIndex
		label = entry.label
		fade = entry.fade
		values = entry.levels
	}
	
	func title(at position: Int) -> String {
		label.isEmpty ? "Cue \(position + 1)" : label
	}
	
	static func seconds(_ value: Double) -> String {
		value > 0 ? "\(value.formatted(.number.precision(.fractionLength(0...1)))) s" : "No fade"
	}
}
