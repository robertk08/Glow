import Foundation

nonisolated struct Show: Identifiable, Codable, Hashable, Sendable {
	var id: String
	var name: String
	
	init(name: String) {
		id = Identifier.fresh()
		self.name = name
	}
}
