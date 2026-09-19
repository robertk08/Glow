import Foundation

nonisolated struct ShowFile: Codable, Sendable {
	nonisolated struct Light: Codable, Sendable {
		var identifier: String
		var typeID: String
		var name: String
		var address: Int
		var sortIndex: Int
		var symbol: String?
		var group: String?
		var invertsPan: Bool?
		var invertsTilt: Bool?
		
		init(identifier: String, typeID: String, name: String, address: Int, sortIndex: Int, symbol: String? = nil, group: String? = nil, invertsPan: Bool? = nil, invertsTilt: Bool? = nil) {
			self.identifier = identifier
			self.typeID = typeID
			self.name = name
			self.address = address
			self.sortIndex = sortIndex
			self.symbol = symbol
			self.group = group
			self.invertsPan = invertsPan
			self.invertsTilt = invertsTilt
		}
		
		init(from decoder: any Decoder) throws {
			let container = try decoder.container(keyedBy: CodingKeys.self)
			identifier = try container.decode(String.self, forKey: .identifier)
			typeID = try container.decodeIfPresent(String.self, forKey: .typeID) ?? container.decode(String.self, forKey: .profileID)
			name = try container.decode(String.self, forKey: .name)
			address = try container.decode(Int.self, forKey: .address)
			sortIndex = try container.decode(Int.self, forKey: .sortIndex)
			symbol = try container.decodeIfPresent(String.self, forKey: .symbol)
			group = try container.decodeIfPresent(String.self, forKey: .group)
			invertsPan = try container.decodeIfPresent(Bool.self, forKey: .invertsPan)
			invertsTilt = try container.decodeIfPresent(Bool.self, forKey: .invertsTilt)
		}
		
		func encode(to encoder: any Encoder) throws {
			var container = encoder.container(keyedBy: CodingKeys.self)
			try container.encode(identifier, forKey: .identifier)
			try container.encode(typeID, forKey: .typeID)
			try container.encode(name, forKey: .name)
			try container.encode(address, forKey: .address)
			try container.encode(sortIndex, forKey: .sortIndex)
			try container.encodeIfPresent(symbol, forKey: .symbol)
			try container.encodeIfPresent(group, forKey: .group)
			try container.encodeIfPresent(invertsPan, forKey: .invertsPan)
			try container.encodeIfPresent(invertsTilt, forKey: .invertsTilt)
		}
		
		private enum CodingKeys: String, CodingKey {
			case identifier, typeID, profileID, name, address, sortIndex, symbol, group, invertsPan, invertsTilt
		}
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
	
	var version: String? = ShowFile.current
	var exportedAt: Date? = .now
	var name: String
	var lights: [Light]
	var groups: [Group]
	var made: [FixtureType]
	var scenes: [Scene]
	
	init(name: String, lights: [Light], groups: [Group], made: [FixtureType], scenes: [Scene]) {
		self.name = name
		self.lights = lights
		self.groups = groups
		self.made = made
		self.scenes = scenes
	}
	
	init(from decoder: any Decoder) throws {
		let container = try decoder.container(keyedBy: CodingKeys.self)
		version = try container.decodeIfPresent(String.self, forKey: .version)
		exportedAt = try container.decodeIfPresent(Date.self, forKey: .exportedAt)
		name = try container.decode(String.self, forKey: .name)
		lights = try container.decodeIfPresent([Light].self, forKey: .lights) ?? []
		groups = try container.decodeIfPresent([Group].self, forKey: .groups) ?? []
		made = try container.decodeIfPresent([FixtureType].self, forKey: .made) ?? []
		scenes = try container.decodeIfPresent([Scene].self, forKey: .scenes) ?? []
	}
	
	private enum CodingKeys: String, CodingKey {
		case version, exportedAt, name, lights, groups, made, scenes
	}
}
