import Foundation

nonisolated struct ShowScene: Codable, Sendable {
	var name: String
	var sortIndex: Int
	var levels: Data
}
