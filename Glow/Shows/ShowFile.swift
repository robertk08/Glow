import Foundation

nonisolated struct ShowFile: Codable, Sendable {
	nonisolated struct Light: Codable, Sendable {
		var identifier: String
		var typeID: String
		var name: String
		var address: Int
		var sortIndex: Int
		var symbol: String?
		var groups: [String] = []
		var invertsPan = false
		var invertsTilt = false
	}
	
	nonisolated struct Group: Codable, Sendable {
		var name: String
		var sortIndex: Int
		var symbol: String?
		var tint: String?
	}
	
	nonisolated struct Scene: Codable, Sendable {
		var name: String
		var sortIndex: Int
		var levels: Data
	}
	
	static let current = "2026-09-19"
	
	var version = ShowFile.current
	var exportedAt = Date.now
	var name: String
	var lights: [Light]
	var groups: [Group]
	var made: [FixtureType]
	var scenes: [Scene]
}
