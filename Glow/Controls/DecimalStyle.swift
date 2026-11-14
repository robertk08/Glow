import Foundation

nonisolated struct DecimalStyle: ParseableFormatStyle, ParseStrategy {
	var parseStrategy: DecimalStyle { self }
	
	func format(_ value: Double) -> String {
		value.formatted(.number.grouping(.never).precision(.fractionLength(0...2)))
	}
	
	func parse(_ value: String) throws -> Double {
		guard let number = Double(value.filter { !$0.isWhitespace }.replacingOccurrences(of: ",", with: ".")), number.isFinite else { throw CocoaError(.formatting) }
		return (number * 100).rounded() / 100
	}
}
