import Foundation

nonisolated struct ShowFile: Codable, Sendable {
	static let format = "glow.show"
	static let current = "2026-09-20"
	
	var format = ShowFile.format
	var version = ShowFile.current
	var exportedAt = Date.now
	var name: String
	var show: ShowContents
	
	var isReadable: Bool {
		format == ShowFile.format && version == ShowFile.current
	}
	
	private enum CodingKeys: String, CodingKey { case format, version, exportedAt, name, show }
	
	init(name: String, show: ShowContents) {
		self.name = name
		self.show = show
	}
	
	init(from decoder: any Decoder) throws {
		let container = try decoder.container(keyedBy: CodingKeys.self)
		format = try container.decodeIfPresent(String.self, forKey: .format) ?? ""
		version = try container.decodeIfPresent(String.self, forKey: .version) ?? ""
		exportedAt = try container.decodeIfPresent(Date.self, forKey: .exportedAt) ?? .now
		name = try container.decodeIfPresent(String.self, forKey: .name) ?? ""
		show = try container.decodeIfPresent(ShowContents.self, forKey: .show) ?? ShowContents()
	}
}
