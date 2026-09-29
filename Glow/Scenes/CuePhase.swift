import Foundation

nonisolated enum CuePhase: Sendable, Equatable {
	case waiting(until: Date)
	case fading(ClosedRange<Date>)
	case following(until: Date)
	case holding
}
