import Foundation

nonisolated struct ShowContents: Codable, Sendable {
	nonisolated struct Light: Codable, Sendable {
		var identifier: String
		var typeID: String
		var name: String
		var address: Int
		var sortIndex: Double
		var symbol: String?
		var groups: [String] = []
		var invertsPan = false
		var invertsTilt = false
		
		private enum CodingKeys: String, CodingKey { case identifier, typeID, name, address, sortIndex, symbol, groups, invertsPan, invertsTilt }
		
		init(identifier: String, typeID: String, name: String, address: Int, sortIndex: Double, symbol: String? = nil, groups: [String] = [], invertsPan: Bool = false, invertsTilt: Bool = false) {
			self.identifier = identifier
			self.typeID = typeID
			self.name = name
			self.address = address
			self.sortIndex = sortIndex
			self.symbol = symbol
			self.groups = groups
			self.invertsPan = invertsPan
			self.invertsTilt = invertsTilt
		}
		
		init(from decoder: any Decoder) throws {
			let container = try decoder.container(keyedBy: CodingKeys.self)
			identifier = try container.decode(String.self, forKey: .identifier)
			typeID = try container.decode(String.self, forKey: .typeID)
			name = try container.decode(String.self, forKey: .name)
			address = try container.decode(Int.self, forKey: .address)
			sortIndex = try container.decodeIfPresent(Double.self, forKey: .sortIndex) ?? 0
			symbol = try container.decodeIfPresent(String.self, forKey: .symbol)
			groups = try container.decodeIfPresent([String].self, forKey: .groups) ?? []
			invertsPan = try container.decodeIfPresent(Bool.self, forKey: .invertsPan) ?? false
			invertsTilt = try container.decodeIfPresent(Bool.self, forKey: .invertsTilt) ?? false
		}
	}
	
	nonisolated struct Group: Codable, Sendable {
		var identifier: String
		var name: String
		var sortIndex: Double
		var symbol: String?
		var tint: String?
		
		private enum CodingKeys: String, CodingKey { case identifier, name, sortIndex, symbol, tint }
		
		init(identifier: String, name: String, sortIndex: Double, symbol: String? = nil, tint: String? = nil) {
			self.identifier = identifier
			self.name = name
			self.sortIndex = sortIndex
			self.symbol = symbol
			self.tint = tint
		}
		
		init(from decoder: any Decoder) throws {
			let container = try decoder.container(keyedBy: CodingKeys.self)
			identifier = try container.decode(String.self, forKey: .identifier)
			name = try container.decode(String.self, forKey: .name)
			sortIndex = try container.decodeIfPresent(Double.self, forKey: .sortIndex) ?? 0
			symbol = try container.decodeIfPresent(String.self, forKey: .symbol)
			tint = try container.decodeIfPresent(String.self, forKey: .tint)
		}
	}
	
	nonisolated struct Scene: Codable, Sendable {
		var identifier: String
		var name: String
		var sortIndex: Double
		var levels: [String: Data]
		
		private enum CodingKeys: String, CodingKey { case identifier, name, sortIndex, levels }
		
		init(identifier: String, name: String, sortIndex: Double, levels: [String: Data]) {
			self.identifier = identifier
			self.name = name
			self.sortIndex = sortIndex
			self.levels = levels
		}
		
		init(from decoder: any Decoder) throws {
			let container = try decoder.container(keyedBy: CodingKeys.self)
			identifier = try container.decode(String.self, forKey: .identifier)
			name = try container.decode(String.self, forKey: .name)
			sortIndex = try container.decodeIfPresent(Double.self, forKey: .sortIndex) ?? 0
			levels = try container.decodeIfPresent([String: Data].self, forKey: .levels) ?? [:]
		}
	}
	
	var lights: [Light] = []
	var groups: [Group] = []
	var made: [FixtureType] = []
	var scenes: [Scene] = []
	
	private enum CodingKeys: String, CodingKey { case lights, groups, made, scenes }
	
	init(lights: [Light] = [], groups: [Group] = [], made: [FixtureType] = [], scenes: [Scene] = []) {
		self.lights = lights
		self.groups = groups
		self.made = made
		self.scenes = scenes
	}
	
	init(from decoder: any Decoder) throws {
		let container = try decoder.container(keyedBy: CodingKeys.self)
		lights = try container.decodeIfPresent([Light].self, forKey: .lights) ?? []
		groups = try container.decodeIfPresent([Group].self, forKey: .groups) ?? []
		made = try container.decodeIfPresent([FixtureType].self, forKey: .made) ?? []
		scenes = try container.decodeIfPresent([Scene].self, forKey: .scenes) ?? []
	}
}
