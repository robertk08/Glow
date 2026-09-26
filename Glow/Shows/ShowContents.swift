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
		
		func encode(to encoder: any Encoder) throws {
			var container = encoder.container(keyedBy: CodingKeys.self)
			try container.encode(identifier, forKey: .identifier)
			try container.encode(typeID, forKey: .typeID)
			try container.encode(name, forKey: .name)
			try container.encode(address, forKey: .address)
			try container.encode(sortIndex, forKey: .sortIndex)
			try container.encodeIfPresent(symbol, forKey: .symbol)
			if !groups.isEmpty { try container.encode(groups, forKey: .groups) }
			if invertsPan { try container.encode(true, forKey: .invertsPan) }
			if invertsTilt { try container.encode(true, forKey: .invertsTilt) }
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
		var loops = false
		
		private enum CodingKeys: String, CodingKey { case identifier, name, sortIndex, loops }
		
		init(identifier: String, name: String, sortIndex: Double, loops: Bool = false) {
			self.identifier = identifier
			self.name = name
			self.sortIndex = sortIndex
			self.loops = loops
		}
		
		init?(identifier: String, body: Data) {
			var reader = ByteReader(body)
			guard reader.byte() == 1, let flags = reader.byte(), let sortIndex = reader.double(), let name = reader.text() else { return nil }
			self.init(identifier: identifier, name: name, sortIndex: sortIndex, loops: flags & 1 != 0)
		}
		
		init(from decoder: any Decoder) throws {
			let container = try decoder.container(keyedBy: CodingKeys.self)
			identifier = try container.decode(String.self, forKey: .identifier)
			name = try container.decode(String.self, forKey: .name)
			sortIndex = try container.decodeIfPresent(Double.self, forKey: .sortIndex) ?? 0
			loops = try container.decodeIfPresent(Bool.self, forKey: .loops) ?? false
		}
		
		var body: Data {
			var writer = ByteWriter()
			writer.byte(1)
			writer.byte(loops ? 1 : 0)
			writer.double(sortIndex)
			writer.text(name)
			return writer.data
		}
	}
	
	nonisolated struct Cue: Codable, Sendable {
		var identifier: String
		var scene: String
		var number: Int
		var name = ""
		var fade = 0.0
		var delay = 0.0
		var trigger = Trigger.go
		var wait = 0.0
		var levels = Data()
		
		private enum CodingKeys: String, CodingKey { case identifier, scene, number, name, fade, delay, trigger, wait, levels }
		
		init(identifier: String, scene: String, number: Int, name: String = "", fade: Double = 0, delay: Double = 0, trigger: Trigger = .go, wait: Double = 0, levels: Data = Data()) {
			self.identifier = identifier
			self.scene = scene
			self.number = number
			self.name = name
			self.fade = fade
			self.delay = delay
			self.trigger = trigger
			self.wait = wait
			self.levels = levels
		}
		
		init?(identifier: String, body: Data) {
			var payload = Data(body.dropFirst())
			
			if body.first == 2 {
				guard let inflated = try? (payload as NSData).decompressed(using: .zlib) as Data else { return nil }
				payload = inflated
			} else if body.first != 1 {
				return nil
			}
			
			var reader = ByteReader(payload)
			guard let (_, scene) = reader.identifier(), let number = reader.number(), let fade = reader.tenths(), let delay = reader.tenths() else { return nil }
			guard let raw = reader.byte(), let trigger = Trigger(rawValue: Int(raw)), let wait = reader.tenths(), let name = reader.text(), Levels(reader.rest) != nil else { return nil }
			self.init(identifier: identifier, scene: scene, number: number, name: name, fade: fade, delay: delay, trigger: trigger, wait: wait, levels: reader.rest)
		}
		
		init(from decoder: any Decoder) throws {
			let container = try decoder.container(keyedBy: CodingKeys.self)
			identifier = try container.decode(String.self, forKey: .identifier)
			scene = try container.decode(String.self, forKey: .scene)
			number = try container.decodeIfPresent(Int.self, forKey: .number) ?? 1000
			name = try container.decodeIfPresent(String.self, forKey: .name) ?? ""
			fade = try container.decodeIfPresent(Double.self, forKey: .fade) ?? 0
			delay = try container.decodeIfPresent(Double.self, forKey: .delay) ?? 0
			trigger = try container.decodeIfPresent(Trigger.self, forKey: .trigger) ?? .go
			wait = try container.decodeIfPresent(Double.self, forKey: .wait) ?? 0
			levels = try container.decodeIfPresent(Data.self, forKey: .levels) ?? Data()
		}
		
		var numberText: String {
			Glow.Cue.text(number)
		}
		
		var title: String {
			name.isEmpty ? "Cue \(numberText)" : name
		}
		
		var body: Data {
			var writer = ByteWriter()
			writer.identifier(scene, tag: 0)
			writer.number(number)
			writer.tenths(fade)
			writer.tenths(delay)
			writer.byte(UInt8(trigger.rawValue))
			writer.tenths(wait)
			writer.text(name)
			writer.bytes([UInt8](levels))
			
			guard let packed = try? (writer.data as NSData).compressed(using: .zlib) as Data, packed.count < writer.data.count else { return Data([1]) + writer.data }
			return Data([2]) + packed
		}
	}
	
	var lights: [Light] = []
	var groups: [Group] = []
	var made: [FixtureType] = []
	var scenes: [Scene] = []
	var cues: [Cue] = []
	var unreadable: Set<String> = []
	
	private enum CodingKeys: String, CodingKey { case lights, groups, made, scenes, cues }
	
	init(lights: [Light] = [], groups: [Group] = [], made: [FixtureType] = [], scenes: [Scene] = [], cues: [Cue] = []) {
		self.lights = lights
		self.groups = groups
		self.made = made
		self.scenes = scenes
		self.cues = cues
	}
	
	init(objects: [(folder: String, id: String, body: Data)]) {
		let decoder = JSONDecoder()
		
		for (folder, id, body) in objects {
			let before = count
			
			switch NodeStore.Folder(rawValue: folder) {
			case .lights: if let light = try? decoder.decode(Light.self, from: body) { lights.append(light) }
			case .groups: if let group = try? decoder.decode(Group.self, from: body) { groups.append(group) }
			case .made: if let type = try? decoder.decode(FixtureType.self, from: body) { made.append(type) }
			case .scenes: if let scene = Scene(identifier: id, body: body) { scenes.append(scene) }
			case .cues: if let cue = Cue(identifier: id, body: body) { cues.append(cue) }
			case nil: continue
			}
			
			if count == before { unreadable.insert("\(folder)/\(id)") }
		}
	}
	
	private var count: Int { lights.count + groups.count + made.count + scenes.count + cues.count }
	
	init(from decoder: any Decoder) throws {
		let container = try decoder.container(keyedBy: CodingKeys.self)
		lights = try container.decodeIfPresent([Light].self, forKey: .lights) ?? []
		groups = try container.decodeIfPresent([Group].self, forKey: .groups) ?? []
		made = try container.decodeIfPresent([FixtureType].self, forKey: .made) ?? []
		scenes = try container.decodeIfPresent([Scene].self, forKey: .scenes) ?? []
		cues = try container.decodeIfPresent([Cue].self, forKey: .cues) ?? []
	}
}
