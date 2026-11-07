import Foundation

nonisolated enum GoboShape: String, Codable, Sendable {
	case open, dot, smallDot, largeDot, ring, rings, tunnel, petals, fourPetals, speckle, breakup
	case cross, diagonalCross, star, starburst, triangle, grid, dashes, dotLine, dotRing
}
