import Foundation

nonisolated struct ShowGroup: Codable, Sendable {
	var name: String
	var sortIndex: Int
	var symbol: String?
	var tint: String?
}
