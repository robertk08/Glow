import Foundation

nonisolated enum Trigger: Int, Codable, Sendable, CaseIterable, Identifiable {
	case go, follow, wait
	
	var id: Int { rawValue }
	
	var name: String {
		switch self {
		case .go: "On Go"
		case .follow: "After Previous"
		case .wait: "Timed"
		}
	}
	
	var symbol: String {
		switch self {
		case .go: "hand.tap"
		case .follow: "arrow.turn.down.right"
		case .wait: "timer"
		}
	}
}
