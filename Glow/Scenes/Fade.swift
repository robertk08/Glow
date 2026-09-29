import Foundation

nonisolated struct Fade: Sendable, Equatable {
	let start: Date
	let end: Date
	var follows = true
	
	func moments(follow: Double?) -> [Date] {
		[start, end] + (follows ? follow.map { [end.addingTimeInterval($0)] } ?? [] : [])
	}
	
	func phase(at date: Date, follow: Double?) -> CuePhase {
		if date < start { return .waiting(until: start) }
		if date < end { return .fading(start...end) }
		if follows, let follow, date < end.addingTimeInterval(follow) { return .following(until: end.addingTimeInterval(follow)) }
		return .holding
	}
}
