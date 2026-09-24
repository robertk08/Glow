import Foundation

nonisolated struct Show: Identifiable, Codable, Hashable, Sendable {
	var id: String
	var name: String
	
	init(name: String) {
		id = Identifier.fresh()
		self.name = Self.fitted(name)
	}
	
	static func fitted(_ name: String) -> String {
		var fitted = ""
		
		for character in name {
			guard fitted.utf8.count + character.utf8.count <= 64 else { break }
			fitted.append(character)
		}
		
		return fitted
	}
}
