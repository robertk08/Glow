import Foundation

nonisolated struct FixtureType: Codable, Hashable, Sendable, Identifiable {
	nonisolated struct Mode: Codable, Hashable, Sendable, Identifiable {
		var id: String?
		var name: String
		var channels: [FixtureChannel]
		
		var width: Int { channels.flatMap(\.offsets).max() ?? 0 }
		
		var attributes: Set<Attribute> { Set(channels.map(\.attribute)) }
		
		var mixesWithFlags: Bool { Set(Emitter.flags).isSubset(of: attributes) }
		
		var movesHead: Bool { attributes.contains(.pan) && attributes.contains(.tilt) }
		
		mutating func renumber() {
			var next = 1
			
			for index in channels.indices {
				channels[index].offset = next
				next += 1
				
				if channels[index].isWide {
					channels[index].fineOffset = next
					next += 1
				}
			}
		}
		
		init(id: String? = nil, name: String, channels: [FixtureChannel]) {
			self.id = id
			self.name = name
			self.channels = channels
		}
		
		init(from decoder: any Decoder) throws {
			let container = try decoder.container(keyedBy: CodingKeys.self)
			id = try container.decodeIfPresent(String.self, forKey: .id)
			name = try container.decode(String.self, forKey: .name)
			channels = try container.decode([FixtureChannel].self, forKey: .channels)
		}
		
		private enum CodingKeys: String, CodingKey {
			case id, name, channels
		}
	}
	
	var id: String
	var manufacturer: String = ""
	var model: String
	var symbol: String = "lightbulb"
	var mixing: ColorMixing = .additive
	var invertsPan = false
	var invertsTilt = false
	var panDegrees: Double?
	var tiltDegrees: Double?
	var modes: [Mode]
	
	var name: String { manufacturer.isEmpty ? model : "\(manufacturer) \(model)" }
	
	func identifier(of mode: Mode) -> String {
		mode.id ?? "\(id)-\(mode.name.replacingOccurrences(of: " ", with: "-").lowercased())"
	}
	
	var fixtureModes: [FixtureMode] {
		modes.map { mode in
			FixtureMode(id: identifier(of: mode), typeID: id, manufacturer: manufacturer, model: model, mode: mode.name, channels: mode.channels, symbol: symbol, mixing: mixing, invertsPan: invertsPan, invertsTilt: invertsTilt, panDegrees: panDegrees, tiltDegrees: tiltDegrees)
		}
	}
	
	static let blank = FixtureType(id: "", model: "", modes: [Mode(name: "1 channel", channels: [FixtureChannel(offset: 1, attribute: .dimmer)])])
	
	init(id: String, manufacturer: String = "", model: String, symbol: String = "lightbulb", mixing: ColorMixing = .additive, invertsPan: Bool = false, invertsTilt: Bool = false, panDegrees: Double? = nil, tiltDegrees: Double? = nil, modes: [Mode]) {
		self.id = id
		self.manufacturer = manufacturer
		self.model = model
		self.symbol = symbol
		self.mixing = mixing
		self.invertsPan = invertsPan
		self.invertsTilt = invertsTilt
		self.panDegrees = panDegrees
		self.tiltDegrees = tiltDegrees
		self.modes = modes
	}
	
	init(from decoder: any Decoder) throws {
		let container = try decoder.container(keyedBy: CodingKeys.self)
		id = try container.decode(String.self, forKey: .id)
		manufacturer = try container.decodeIfPresent(String.self, forKey: .manufacturer) ?? ""
		model = try container.decode(String.self, forKey: .model)
		symbol = try container.decodeIfPresent(String.self, forKey: .symbol) ?? "lightbulb"
		mixing = try container.decodeIfPresent(ColorMixing.self, forKey: .mixing) ?? .additive
		invertsPan = try container.decodeIfPresent(Bool.self, forKey: .invertsPan) ?? false
		invertsTilt = try container.decodeIfPresent(Bool.self, forKey: .invertsTilt) ?? false
		panDegrees = try container.decodeIfPresent(Double.self, forKey: .panDegrees)
		tiltDegrees = try container.decodeIfPresent(Double.self, forKey: .tiltDegrees)
		modes = try container.decode([Mode].self, forKey: .modes)
	}
	
	func encode(to encoder: any Encoder) throws {
		var container = encoder.container(keyedBy: CodingKeys.self)
		try container.encode(id, forKey: .id)
		if !manufacturer.isEmpty { try container.encode(manufacturer, forKey: .manufacturer) }
		try container.encode(model, forKey: .model)
		try container.encode(symbol, forKey: .symbol)
		if mixing != .additive { try container.encode(mixing, forKey: .mixing) }
		if invertsPan { try container.encode(true, forKey: .invertsPan) }
		if invertsTilt { try container.encode(true, forKey: .invertsTilt) }
		try container.encodeIfPresent(panDegrees, forKey: .panDegrees)
		try container.encodeIfPresent(tiltDegrees, forKey: .tiltDegrees)
		try container.encode(modes, forKey: .modes)
	}
	
	private enum CodingKeys: String, CodingKey {
		case id, manufacturer, model, symbol, mixing, invertsPan, invertsTilt, panDegrees, tiltDegrees, modes
	}
}
