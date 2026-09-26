import SwiftData
import SwiftUI

@Model
final class Cue {
	var identifier: String = Identifier.fresh()
	var lookID: String = ""
	var number: Int = 1000
	var name: String = ""
	var fade: Double = 0
	var delay: Double = 0
	var triggerValue: Int = 0
	var wait: Double = 0
	var values: Data = Data()
	
	init(lookID: String, number: Int, fade: Double, levels: Levels) {
		identifier = Identifier.fresh()
		self.lookID = lookID
		self.number = number
		self.fade = fade
		values = levels.data
	}
	
	var trigger: Trigger {
		get { Trigger(rawValue: triggerValue) ?? .go }
		set { triggerValue = newValue.rawValue }
	}
	
	var levels: Levels {
		get { Levels(values) ?? Levels() }
		set { values = newValue.data }
	}
	
	var numberText: String {
		Self.text(number)
	}
	
	var title: String {
		entry.title
	}
	
	var entry: ShowContents.Cue {
		ShowContents.Cue(identifier: identifier, scene: lookID, number: number, name: name, fade: fade, delay: delay, trigger: trigger, wait: wait, levels: values)
	}
	
	func take(_ entry: ShowContents.Cue) {
		identifier = entry.identifier
		lookID = entry.scene
		number = entry.number
		name = entry.name
		fade = entry.fade
		delay = entry.delay
		trigger = entry.trigger
		wait = entry.wait
		values = entry.levels
	}
	
	static func text(_ number: Int) -> String {
		var part = String(format: "%03d", number % 1000)
		
		while part.hasSuffix("0") {
			part.removeLast()
		}
		
		return part.isEmpty ? "\(number / 1000)" : "\(number / 1000).\(part)"
	}
	
	static func seconds(_ value: Double, zero: String = "0 s") -> String {
		value > 0 ? "\(value.formatted(.number.precision(.fractionLength(0...1)))) s" : zero
	}
	
	static func number(_ text: String) -> Int? {
		guard let value = Double(text.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: ".")), value > 0, value < 100_000 else { return nil }
		return Int((value * 1000).rounded())
	}
	
	static func number(after previous: Int?, before next: Int?) -> Int? {
		guard let previous else {
			guard let next else { return 1000 }
			return number(between: 0, and: next)
		}
		
		guard let next else { return (previous / 1000 + 1) * 1000 }
		return number(between: previous, and: next)
	}
	
	private static func number(between low: Int, and high: Int) -> Int? {
		let middle = (low + high) / 2
		
		for step in [1000, 500, 100, 50, 10, 5, 1] {
			let candidate = middle / step * step
			if candidate > low && candidate < high { return candidate }
		}
		
		return nil
	}
}
