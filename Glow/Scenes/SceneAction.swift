import Foundation

nonisolated enum SceneAction: Int, Codable, Sendable, CaseIterable, Identifiable {
	case toggle, flash, next, back, update
	
	static let taps: [SceneAction] = [.toggle, .flash, .next]
	
	var id: Int { rawValue }
	
	var name: String {
		switch self {
		case .toggle: "On and Off"
		case .flash: "Flash"
		case .next: "Next"
		case .back: "Back"
		case .update: "Update"
		}
	}
	
	var tapName: String {
		switch self {
		case .toggle: "Turns It On and Off"
		case .flash: "Flashes It While Held"
		default: "Runs the Next Cue"
		}
	}
	
	var symbol: String {
		switch self {
		case .toggle: "power"
		case .flash: "bolt.fill"
		case .next: "forward.end.fill"
		case .back: "backward.end.fill"
		case .update: "arrow.triangle.2.circlepath"
		}
	}
}
