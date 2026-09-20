import Foundation

nonisolated struct ShowList: Codable, Sendable {
	var active = ""
	var shows: [Show] = []
	
	private enum CodingKeys: String, CodingKey { case active, shows }
	
	init(active: String, shows: [Show]) {
		self.active = active
		self.shows = shows
	}
	
	init(from decoder: any Decoder) throws {
		let container = try decoder.container(keyedBy: CodingKeys.self)
		active = try container.decodeIfPresent(String.self, forKey: .active) ?? ""
		shows = try container.decodeIfPresent([Show].self, forKey: .shows) ?? []
	}
	
	var activeShow: Show? {
		shows.first { $0.id == active } ?? shows.first
	}
}
