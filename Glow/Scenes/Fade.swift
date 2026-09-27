import Foundation

nonisolated struct Fade: Sendable, Equatable {
	let start: Date
	let end: Date
	
	func fraction(at date: Date) -> Double {
		guard end > start else { return date >= start ? 1 : 0 }
		return min(max(date.timeIntervalSince(start) / end.timeIntervalSince(start), 0), 1)
	}
}
