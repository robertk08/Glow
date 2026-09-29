import Foundation

nonisolated enum TileSize: Int, Codable, Sendable, CaseIterable, Identifiable {
	case small, wide, large
	
	var id: Int { rawValue }
	
	var name: String {
		switch self {
		case .small: "Small"
		case .wide: "Wide"
		case .large: "Large"
		}
	}
	
	var columns: Int {
		self == .small ? 1 : 2
	}
	
	var rows: Int {
		self == .large ? 2 : 1
	}
}
