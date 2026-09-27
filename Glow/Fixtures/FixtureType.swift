import Foundation

nonisolated struct FixtureType: Codable, Hashable, Sendable, Identifiable {
	nonisolated enum Dimming: Sendable, Equatable {
		case channel(FixtureChannel)
		case band(FixtureChannel, from: UInt8, to: UInt8, open: UInt8?)
		case emitters([FixtureChannel])
		case none
	}
	
	var id: String
	var manufacturer: String = ""
	var model: String
	var mode: String = ""
	var symbol: String = "lightbulb"
	var mixing: ColorMixing = .additive
	var invertsPan = false
	var invertsTilt = false
	var panDegrees: Double?
	var tiltDegrees: Double?
	var channels: [FixtureChannel]
	
	var name: String { manufacturer.isEmpty ? model : "\(manufacturer) \(model)" }
	var channelCount: Int { channels.reduce(0) { max($0, $1.fineOffset ?? 0, $1.offset) } }
	
	func channel(_ attribute: Attribute) -> FixtureChannel? {
		channels.first { $0.attribute == attribute }
	}
	
	var emitterChannels: [FixtureChannel] { channels.filter(\.attribute.isEmitter) }
	var emitters: [Attribute] { emitterChannels.map(\.attribute) }
	var mixesColor: Bool { emitterChannels.count >= 3 }
	var movesHead: Bool { channel(.pan) != nil && channel(.tilt) != nil }
	
	var groups: [FeatureGroup] {
		FeatureGroup.allCases.filter { group in channels.contains { $0.attribute.group == group } }
	}
	
	func channels(in group: FeatureGroup) -> [FixtureChannel] {
		channels.filter { $0.attribute.group == group }
	}
	
	var defaults: [UInt8] {
		var values = [UInt8](repeating: 0, count: channelCount)
		
		for channel in channels {
			if channel.offset > 0 && channel.offset <= channelCount { values[channel.offset - 1] = channel.defaultValue }
			if let fine = channel.fineOffset, fine > 0 && fine <= channelCount { values[fine - 1] = channel.fineDefaultValue }
		}
		
		return values
	}
	
	var dimming: Dimming {
		if let dedicated = channel(.dimmer) {
			return .channel(dedicated)
		}
		
		for channel in channels {
			guard let band = channel.functions.first(where: { $0.purpose == .dim }) else { continue }
			let open = channel.functions.first { $0.purpose == .open }
			return .band(channel, from: band.from, to: band.to, open: open?.from)
		}
		
		guard mixing == .additive else { return .none }
		let emitters = emitterChannels
		return emitters.isEmpty ? .none : .emitters(emitters)
	}
	
	var dims: Bool { dimming != .none }
	
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
	
	var mixesWithFlags: Bool { Set(Emitter.flags).isSubset(of: Set(channels.map(\.attribute))) }
	
	static let blank = FixtureType(id: "", model: "", channels: [FixtureChannel(offset: 1, attribute: .dimmer)])
	
	init(id: String, manufacturer: String = "", model: String, mode: String = "", symbol: String = "lightbulb", mixing: ColorMixing = .additive, invertsPan: Bool = false, invertsTilt: Bool = false, panDegrees: Double? = nil, tiltDegrees: Double? = nil, channels: [FixtureChannel]) {
		self.id = id
		self.manufacturer = manufacturer
		self.model = model
		self.mode = mode
		self.symbol = symbol
		self.mixing = mixing
		self.invertsPan = invertsPan
		self.invertsTilt = invertsTilt
		self.panDegrees = panDegrees
		self.tiltDegrees = tiltDegrees
		self.channels = channels
	}
	
	init(from decoder: any Decoder) throws {
		let container = try decoder.container(keyedBy: CodingKeys.self)
		id = try container.decode(String.self, forKey: .id)
		manufacturer = try container.decodeIfPresent(String.self, forKey: .manufacturer) ?? ""
		model = try container.decode(String.self, forKey: .model)
		mode = try container.decodeIfPresent(String.self, forKey: .mode) ?? ""
		symbol = try container.decodeIfPresent(String.self, forKey: .symbol) ?? "lightbulb"
		mixing = try container.decodeIfPresent(ColorMixing.self, forKey: .mixing) ?? .additive
		invertsPan = try container.decodeIfPresent(Bool.self, forKey: .invertsPan) ?? false
		invertsTilt = try container.decodeIfPresent(Bool.self, forKey: .invertsTilt) ?? false
		panDegrees = try container.decodeIfPresent(Double.self, forKey: .panDegrees)
		tiltDegrees = try container.decodeIfPresent(Double.self, forKey: .tiltDegrees)
		channels = try container.decode([FixtureChannel].self, forKey: .channels)
	}
	
	func encode(to encoder: any Encoder) throws {
		var container = encoder.container(keyedBy: CodingKeys.self)
		try container.encode(id, forKey: .id)
		if !manufacturer.isEmpty { try container.encode(manufacturer, forKey: .manufacturer) }
		try container.encode(model, forKey: .model)
		if !mode.isEmpty { try container.encode(mode, forKey: .mode) }
		try container.encode(symbol, forKey: .symbol)
		if mixing != .additive { try container.encode(mixing, forKey: .mixing) }
		if invertsPan { try container.encode(true, forKey: .invertsPan) }
		if invertsTilt { try container.encode(true, forKey: .invertsTilt) }
		try container.encodeIfPresent(panDegrees, forKey: .panDegrees)
		try container.encodeIfPresent(tiltDegrees, forKey: .tiltDegrees)
		try container.encode(channels, forKey: .channels)
	}
	
	private enum CodingKeys: String, CodingKey {
		case id, manufacturer, model, mode, symbol, mixing, invertsPan, invertsTilt, panDegrees, tiltDegrees, channels
	}
}
