import Foundation

nonisolated struct ShowFile: Codable, Sendable {
	static let current = "2026-09-17"
	
	struct Light: Codable, Sendable {
		var identifier: String
		var profileID: String
		var name: String
		var address: Int
		var sortIndex: Int
		var symbol: String?
		var tint: String?
		var group: String?
	}
	
	struct Group: Codable, Sendable {
		var name: String
		var sortIndex: Int
		var symbol: String?
		var tint: String?
	}
	
	struct Profile: Codable, Sendable {
		var identifier: String
		var name: String
		var symbol: String
		var channels: [CustomChannel]
		var isSubtractive: Bool?
	}
	
	struct Scene: Codable, Sendable {
		var name: String
		var sortIndex: Int
		var levels: Data
	}
	
	var version: String? = ShowFile.current
	var exportedAt: Date? = .now
	var name: String
	var lights: [Light]
	var groups: [Group]
	var profiles: [Profile]
	var scenes: [Scene]
}
