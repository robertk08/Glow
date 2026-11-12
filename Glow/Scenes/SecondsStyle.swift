import Foundation

nonisolated struct SecondsStyle: ParseableFormatStyle, ParseStrategy {
	var parseStrategy: SecondsStyle { self }
	
	func format(_ value: Double) -> String {
		value.formatted(.number.grouping(.never).precision(.fractionLength(0...2)))
	}
	
	func parse(_ value: String) throws -> Double {
		guard let seconds = Double(value.filter { !$0.isWhitespace }.replacingOccurrences(of: ",", with: ".")), seconds.isFinite else { throw CocoaError(.formatting) }
		return seconds
	}
}
