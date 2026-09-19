import Foundation

nonisolated struct ShowProfile: Codable, Sendable {
	var identifier: String
	var name: String
	var symbol: String
	var channels: [CustomChannel]
	var isSubtractive: Bool?
}
