import Foundation

nonisolated enum FeatureGroup: String, Codable, Sendable, CaseIterable, Identifiable {
	case dimmer, color, position, gobo, beam, control
	
	var id: String { rawValue }
	
	var name: String {
		switch self {
		case .dimmer: "Intensity"
		case .color: "Color"
		case .position: "Position"
		case .gobo: "Gobo"
		case .beam: "Beam"
		case .control: "Control"
		}
	}
	
	var symbol: String {
		switch self {
		case .dimmer: "sun.max"
		case .color: "paintpalette"
		case .position: "move.3d"
		case .gobo: "circle.hexagongrid"
		case .beam: "light.beacon.max"
		case .control: "gearshape"
		}
	}
}
