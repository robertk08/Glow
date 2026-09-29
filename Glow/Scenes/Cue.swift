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
	
	var number: String {
		Self.number(sortIndex)
	}
	
	var title: String {
		label.isEmpty ? "Cue \(number)" : label
	}
	
	static func number(_ sortIndex: Double) -> String {
		sortIndex.formatted(.number.precision(.fractionLength(0...3)).grouping(.never))
	}
	
	var times: [(time: CueTime, seconds: Double)] {
		var times: [(time: CueTime, seconds: Double)] = fade > 0 ? [(.fade, fade)] : []
		if delay > 0 { times.append((.delay, delay)) }
		if let follow { times.append((.follow, follow)) }
		return times
	}
	
	static func seconds(_ value: Double) -> String {
		"\(value.formatted(.number.precision(.fractionLength(0...1)))) s"
	}
}
