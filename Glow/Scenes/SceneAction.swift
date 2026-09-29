import Foundation

nonisolated enum SceneAction: Int, Codable, Sendable, CaseIterable, Identifiable {
	case toggle = 0
	case flash = 1
	case next = 2
	case back = 3
	case open = 5
	
	static let taps: [SceneAction] = [.next, .toggle, .flash, .open]
	static let buttons: [SceneAction] = [.toggle, .flash, .next, .back]
	
	var id: Int { rawValue }
	
	var name: String {
		switch self {
		case .toggle: "On and Off"
		case .flash: "Flash"
		case .next: "Next"
		case .back: "Back"
		case .open: "Open"
		}
	}
	
	var tapName: String {
		switch self {
		case .toggle: "Turns It On and Off"
		case .flash: "Flashes It While Held"
		case .open: "Opens It"
		default: "Runs the Next Cue"
		}
	}
	
	var symbol: String {
		switch self {
		case .toggle: "playpause.fill"
		case .flash: "bolt.fill"
		case .next: "forward.end.fill"
		case .back: "backward.end.fill"
		case .open: "list.bullet"
		}
	}
	
	func name(isOn: Bool) -> String {
		guard self == .toggle else { return name }
		return isOn ? "Turn Off" : "Turn On"
	}
	
	func symbol(isOn: Bool) -> String {
		guard self == .toggle else { return symbol }
		return isOn ? "stop.fill" : "play.fill"
	}
}
