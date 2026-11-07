import Foundation

nonisolated enum CuePhase: Sendable {
	case waiting(until: Date)
	case fading(ClosedRange<Date>)
	case following(until: Date)
	case holding
}
