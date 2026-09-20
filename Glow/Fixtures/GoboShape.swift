import Foundation

nonisolated enum GoboShape: String, Codable, Sendable, CaseIterable, Identifiable {
	case open, dot, smallDot, largeDot, ring, rings, tunnel, petals, fourPetals, speckle, breakup
	case cross, diagonalCross, star, starburst, triangle, grid, dashes, dotLine, dotRing

	var id: String { rawValue }

	var name: String {
		switch self {
		case .open: "Open"
		case .dot: "Dot"
		case .smallDot: "Small dot"
		case .largeDot: "Large dot"
		case .ring: "Ring"
		case .rings: "Rings"
		case .tunnel: "Tunnel"
		case .petals: "Petals"
		case .fourPetals: "Four petals"
		case .speckle: "Speckle"
		case .breakup: "Breakup"
		case .cross: "Cross"
		case .diagonalCross: "Diagonal cross"
		case .star: "Star"
		case .starburst: "Starburst"
		case .triangle: "Triangle"
		case .grid: "Grid"
		case .dashes: "Dashes"
		case .dotLine: "Dot line"
		case .dotRing: "Dot ring"
		}
	}
}
