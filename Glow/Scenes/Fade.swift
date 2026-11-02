import SwiftUI

nonisolated struct Fade: Sendable, Equatable {
	let start: Date
	let end: Date
	var follows = true
	
	func moments(follow: Double?) -> [Date] {
		[start, end] + (follows ? follow.map { [end.addingTimeInterval($0)] } ?? [] : [])
	}
	
	var rise: Animation {
		let duration = end.timeIntervalSince(start)
		guard duration > 0 else { return .snappy(duration: 0.25) }
		return .linear(duration: duration).delay(max(start.timeIntervalSinceNow, 0))
	}
	
	static func fall(over seconds: Double) -> Animation {
		guard seconds > 0 else { return .snappy(duration: 0.25) }
		return .linear(duration: seconds)
	}
	
	func phase(at date: Date, follow: Double?) -> CuePhase {
		if date < start { return .waiting(until: start) }
		if date < end { return .fading(start...end) }
		if follows, let follow, date < end.addingTimeInterval(follow) { return .following(until: end.addingTimeInterval(follow)) }
		return .holding
	}
}
