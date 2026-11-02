import Foundation

nonisolated enum CueTime: Sendable {
	case fade, delay, follow
	
	var name: String {
		switch self {
		case .fade: "Fade"
		case .delay: "Wait"
		case .follow: "Next Cue"
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
