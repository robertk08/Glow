import Foundation

nonisolated struct ShowLight: Codable, Sendable {
	var identifier: String
	var profileID: String
	var name: String
	var address: Int
	var sortIndex: Int
	var symbol: String?
	var group: String?
	var invertsPan: Bool?
	var invertsTilt: Bool?
}
