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
		var symbol: String?
		var tint: String?
		var tap = SceneAction.toggle
		var buttons: [SceneAction] = []
		
		private enum CodingKeys: String, CodingKey { case identifier, name, sortIndex, symbol, tint, tap, buttons }
		
		init(identifier: String, name: String, sortIndex: Double, symbol: String? = nil, tint: String? = nil, tap: SceneAction = .toggle, buttons: [SceneAction] = []) {
			self.identifier = identifier
			self.name = name
			self.sortIndex = sortIndex
			self.symbol = symbol
			self.tint = tint
			self.tap = tap
			self.buttons = buttons
		}
		
		init?(identifier: String, body: Data) {
			var reader = ByteReader(body)
			guard reader.byte() == 4, let tap = reader.byte().flatMap({ SceneAction(rawValue: Int($0)) }), let count = reader.byte(), let buttons = reader.bytes(Int(count)) else { return nil }
			guard let sortIndex = reader.order(), let name = reader.text(), let symbol = reader.text(), let tint = reader.text() else { return nil }
			self.init(identifier: identifier, name: name, sortIndex: sortIndex, symbol: symbol.isEmpty ? nil : symbol, tint: tint.isEmpty ? nil : tint, tap: tap, buttons: buttons.compactMap { SceneAction(rawValue: Int($0)) })
		}
		
		init(from decoder: any Decoder) throws {
			let container = try decoder.container(keyedBy: CodingKeys.self)
			identifier = try container.decode(String.self, forKey: .identifier)
			name = try container.decode(String.self, forKey: .name)
			sortIndex = try container.decodeIfPresent(Double.self, forKey: .sortIndex) ?? 0
			symbol = try container.decodeIfPresent(String.self, forKey: .symbol)
			tint = try container.decodeIfPresent(String.self, forKey: .tint)
			tap = try container.decodeIfPresent(SceneAction.self, forKey: .tap) ?? .toggle
			buttons = try container.decodeIfPresent([SceneAction].self, forKey: .buttons) ?? []
		}
		
		var body: Data {
			var writer = ByteWriter()
			writer.byte(4)
			writer.byte(UInt8(tap.rawValue))
			writer.byte(UInt8(buttons.count))
			writer.bytes(buttons.map { UInt8($0.rawValue) })
			writer.order(sortIndex)
			writer.text(name)
			writer.text(symbol ?? "")
			writer.text(tint ?? "")
			return writer.data
		}
	}
	
	nonisolated struct Cue: Codable, Sendable {
		var identifier: String
		var scene: String
		var sortIndex: Double
		var label = ""
		var fade = 0.0
		var delay = 0.0
		var follow: Double?
		var levels = Data()
		
		private enum CodingKeys: String, CodingKey { case identifier, scene, sortIndex, label, fade, delay, follow, levels }
		
		init(identifier: String, scene: String, sortIndex: Double, label: String = "", fade: Double = 0, delay: Double = 0, follow: Double? = nil, levels: Data = Data()) {
			self.identifier = identifier
			self.scene = scene
			self.sortIndex = sortIndex
			self.label = label
			self.fade = fade
			self.delay = delay
			self.follow = follow
			self.levels = levels
		}
		
		init?(identifier: String, body: Data) {
			var payload = Data(body.dropFirst())
			
			if body.first == 8 {
				guard let inflated = try? (payload as NSData).decompressed(using: .zlib) as Data else { return nil }
				payload = inflated
			} else if body.first != 7 {
				return nil
			}
			
			var reader = ByteReader(payload)
			guard let (_, scene) = reader.identifier(), let sortIndex = reader.order(), let fade = reader.tenths(), let delay = reader.tenths(), let follow = reader.number() else { return nil }
			guard let label = reader.text() else { return nil }
			let levels = reader.rest
			guard Levels.read(levels, { _, _, _ in }) else { return nil }
			self.init(identifier: identifier, scene: scene, sortIndex: sortIndex, label: label, fade: fade, delay: delay, follow: follow == 0 ? nil : Double(follow - 1) / 10, levels: levels)
		}
		
		init(from decoder: any Decoder) throws {
			let container = try decoder.container(keyedBy: CodingKeys.self)
			identifier = try container.decode(String.self, forKey: .identifier)
			scene = try container.decode(String.self, forKey: .scene)
			sortIndex = try container.decodeIfPresent(Double.self, forKey: .sortIndex) ?? 0
			label = try container.decodeIfPresent(String.self, forKey: .label) ?? ""
			fade = try container.decodeIfPresent(Double.self, forKey: .fade) ?? 0
			delay = try container.decodeIfPresent(Double.self, forKey: .delay) ?? 0
			follow = try container.decodeIfPresent(Double.self, forKey: .follow)
			levels = try container.decodeIfPresent(Data.self, forKey: .levels) ?? Data()
		}
		
		var body: Data {
			var writer = ByteWriter()
			writer.identifier(scene, tag: 0)
			writer.order(sortIndex)
			writer.tenths(fade)
			writer.tenths(delay)
			writer.number(follow.map { Int(($0 * 10).rounded()) + 1 } ?? 0)
			writer.text(label)
			writer.bytes([UInt8](levels))
			
			guard let packed = try? (writer.data as NSData).compressed(using: .zlib) as Data, packed.count < writer.data.count else { return Data([7]) + writer.data }
			return Data([8]) + packed
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
