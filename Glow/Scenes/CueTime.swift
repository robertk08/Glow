import Foundation

nonisolated enum CueTime: Sendable {
	case fade, delay, follow
	
	var name: String {
		switch self {
		case .fade: "Fade"
		case .delay: "Delay"
		case .follow: "Follow"
		}
	}
	
	var symbol: String {
		switch self {
		case .fade: "circle.lefthalf.filled"
		case .delay: "hourglass"
		case .follow: "arrow.turn.down.right"
		}
	}
}
