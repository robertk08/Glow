import Foundation

nonisolated struct ShowFile: Codable, Sendable {
	static let current = "2026-09-18"
	
	var version: String? = ShowFile.current
	var exportedAt: Date? = .now
	var name: String
	var lights: [ShowLight]
	var groups: [ShowGroup]
	var profiles: [ShowProfile]
	var scenes: [ShowScene]
}
