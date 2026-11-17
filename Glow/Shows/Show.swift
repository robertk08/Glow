import Foundation

nonisolated struct Show: Identifiable, Codable, Equatable, Sendable {
	var id: String
	var name: String
	var sendsAllChannels = false
	
	private enum CodingKeys: String, CodingKey { case id, name, sendsAllChannels }
	
	init(name: String) {
		id = Identifier.fresh()
		self.name = Self.fitted(name)
	}
	
	init(from decoder: any Decoder) throws {
		let container = try decoder.container(keyedBy: CodingKeys.self)
		id = try container.decode(String.self, forKey: .id)
		name = try container.decode(String.self, forKey: .name)
		sendsAllChannels = try container.decodeIfPresent(Bool.self, forKey: .sendsAllChannels) ?? false
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
