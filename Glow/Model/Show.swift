import Foundation

nonisolated struct Show: Identifiable, Codable, Hashable, Sendable {
	var id: String
	var name: String
	var createdAt: Date
	
	init(name: String) {
		id = UUID().uuidString
		self.name = name
		createdAt = .now
	}
}
