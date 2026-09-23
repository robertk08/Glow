import Foundation

nonisolated enum GoboShape: String, Codable, Sendable, CaseIterable, Identifiable {
	case open, dot, smallDot, largeDot, ring, rings, tunnel, petals, fourPetals, speckle, breakup
	case cross, diagonalCross, star, starburst, triangle, grid, dashes, dotLine, dotRing

	var id: String { rawValue }

	var name: String { Spoken.words(rawValue) }
}
