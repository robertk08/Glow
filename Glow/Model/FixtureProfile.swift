import Foundation

nonisolated struct ChannelRange: Codable, Hashable, Sendable, Identifiable {
	nonisolated enum Kind: String, Codable, Sendable {
		case discrete, proportional
	}
	
	var from: UInt8
	var to: UInt8
	var label: String
	var kind: Kind = .discrete
	var requiresConfirmation = false
	var releasesMix = false
	
	var id: String { "\(from)-\(to)" }
	var midpoint: UInt8 { UInt8((Int(from) + Int(to)) / 2) }
	
	func contains(_ value: UInt8) -> Bool { (from...to).contains(value) }
	
	private enum CodingKeys: String, CodingKey {
		case from, to, label, kind, requiresConfirmation, releasesMix
	}
	
	init(from: UInt8, to: UInt8, label: String, kind: Kind = .discrete) {
		self.from = from
		self.to = to
		self.label = label
		self.kind = kind
	}
	
	init(from decoder: any Decoder) throws {
		let container = try decoder.container(keyedBy: CodingKeys.self)
		let start = try container.decode(UInt8.self, forKey: .from)
		let end = try container.decode(UInt8.self, forKey: .to)
		from = min(start, end)
		to = max(start, end)
		label = try container.decode(String.self, forKey: .label)
		kind = try container.decodeIfPresent(Kind.self, forKey: .kind) ?? .discrete
		requiresConfirmation = try container.decodeIfPresent(Bool.self, forKey: .requiresConfirmation) ?? false
		releasesMix = try container.decodeIfPresent(Bool.self, forKey: .releasesMix) ?? false
	}
}

nonisolated struct ProfileChannel: Decodable, Hashable, Sendable, Identifiable {
	var offset: Int
	var role: ChannelRole
	var name: String
	var isFine = false
	var defaultValue: UInt8 = 0
	var ranges: [ChannelRange] = []
	
	var id: Int { offset }
	
	func range(containing value: UInt8) -> ChannelRange? {
		ranges.first { $0.contains(value) }
	}
	
	private enum CodingKeys: String, CodingKey {
		case offset, role, name, isFine, defaultValue, ranges
	}
	
	init(offset: Int, role: ChannelRole, name: String? = nil, isFine: Bool = false, defaultValue: UInt8 = 0, ranges: [ChannelRange] = []) {
		self.offset = offset
		self.role = role
		self.name = name ?? role.name
		self.isFine = isFine
		self.defaultValue = defaultValue
		self.ranges = ranges
	}
	
	init(from decoder: any Decoder) throws {
		let container = try decoder.container(keyedBy: CodingKeys.self)
		offset = try container.decode(Int.self, forKey: .offset)
		role = try container.decodeIfPresent(ChannelRole.self, forKey: .role) ?? .custom
		name = try container.decodeIfPresent(String.self, forKey: .name) ?? role.name
		isFine = try container.decodeIfPresent(Bool.self, forKey: .isFine) ?? false
		defaultValue = try container.decodeIfPresent(UInt8.self, forKey: .defaultValue) ?? 0
		ranges = try container.decodeIfPresent([ChannelRange].self, forKey: .ranges) ?? []
	}
}

nonisolated struct FixtureProfile: Decodable, Hashable, Sendable, Identifiable {
	nonisolated enum Dimming: Sendable, Equatable {
		case channel(ProfileChannel)
		case band(ProfileChannel, from: UInt8, to: UInt8, open: UInt8?)
		case emitters([ProfileChannel])
		case none
	}
	
	var id: String
	var manufacturer: String
	var model: String
	var mode: String
	var channels: [ProfileChannel]
	var symbol: String
	var mixing: ColorMixing
	var invertsPan: Bool
	var invertsTilt: Bool
	var panDegrees: Double?
	var tiltDegrees: Double?
	
	var name: String { manufacturer.isEmpty ? model : "\(manufacturer) \(model)" }
	var channelCount: Int { channels.map(\.offset).max() ?? 0 }
	
	func channel(_ role: ChannelRole, fine: Bool = false) -> ProfileChannel? {
		channels.first { $0.role == role && $0.isFine == fine }
	}
	
	var emitterChannels: [ProfileChannel] {
		channels.filter { $0.role.isEmitter && !$0.isFine }
	}
	
	var emitters: [ChannelRole] { emitterChannels.map(\.role) }
	
	var movesHead: Bool { channel(.pan) != nil && channel(.tilt) != nil }
	
	var abilities: [String] {
		var found: [String] = []
		if dims { found.append("Dimmer") }
		if mixesColor { found.append(mixing == .subtractive ? "CMY" : "Colour") }
		if channel(.colorWheel) != nil || channel(.colorMacro) != nil { found.append("Colour wheel") }
		if movesHead { found.append("Moving head") }
		if channel(.shutter) != nil { found.append("Strobe") }
		if channel(.gobo) != nil { found.append("Gobo") }
		if channel(.zoom) != nil { found.append("Zoom") }
		if channel(.focus) != nil { found.append("Focus") }
		if channel(.prism) != nil { found.append("Prism") }
		if channel(.frost) != nil { found.append("Frost") }
		return found
	}
	var mixesColor: Bool { emitterChannels.count >= 3 }
	
	var defaults: [UInt8] {
		var values = [UInt8](repeating: 0, count: channelCount)
		for channel in channels where (1...channelCount).contains(channel.offset) {
			values[channel.offset - 1] = channel.defaultValue
		}
		return values
	}
	
	var dimming: Dimming {
		if let dedicated = channel(.intensity) {
			return .channel(dedicated)
		}
		if let shutter = channel(.shutter), let band = Self.dimmingBand(of: shutter) {
			let open = shutter.ranges.first {
				$0.kind == .discrete && $0.label.localizedCaseInsensitiveContains("open")
			}
			return .band(shutter, from: band.from, to: band.to, open: open?.from)
		}
		guard mixing == .additive else { return .none }
		let emitters = emitterChannels
		return emitters.isEmpty ? .none : .emitters(emitters)
	}
	
	var dims: Bool { dimming != .none }
	
	private static func dimmingBand(of channel: ProfileChannel) -> ChannelRange? {
		let proportional = channel.ranges.filter { $0.kind == .proportional }
		if let named = proportional.first(where: { $0.label.localizedCaseInsensitiveContains("dim") }) {
			return named
		}
		return proportional
			.filter { !$0.label.localizedCaseInsensitiveContains("strob") }
			.min { $0.from < $1.from }
	}
	
	init(id: String, manufacturer: String = "", model: String, mode: String = "", channels: [ProfileChannel], symbol: String = "lightbulb", mixing: ColorMixing = .additive, invertsPan: Bool = false, invertsTilt: Bool = false, panDegrees: Double? = nil, tiltDegrees: Double? = nil) {
		self.id = id
		self.manufacturer = manufacturer
		self.model = model
		self.mode = mode
		self.channels = channels
		self.symbol = symbol
		self.mixing = mixing
		self.invertsPan = invertsPan
		self.invertsTilt = invertsTilt
		self.panDegrees = panDegrees
		self.tiltDegrees = tiltDegrees
	}
	
	init(from decoder: any Decoder) throws {
		let container = try decoder.container(keyedBy: CodingKeys.self)
		id = try container.decode(String.self, forKey: .id)
		manufacturer = try container.decodeIfPresent(String.self, forKey: .manufacturer) ?? ""
		model = try container.decode(String.self, forKey: .model)
		mode = try container.decodeIfPresent(String.self, forKey: .mode) ?? ""
		channels = try container.decode([ProfileChannel].self, forKey: .channels)
		symbol = try container.decodeIfPresent(String.self, forKey: .symbolName) ?? "lightbulb"
		mixing = try container.decodeIfPresent(ColorMixing.self, forKey: .colorMixing) ?? .additive
		invertsPan = try container.decodeIfPresent(Bool.self, forKey: .invertsPan) ?? false
		invertsTilt = try container.decodeIfPresent(Bool.self, forKey: .invertsTilt) ?? false
		panDegrees = try container.decodeIfPresent(Double.self, forKey: .panDegrees)
		tiltDegrees = try container.decodeIfPresent(Double.self, forKey: .tiltDegrees)
	}
	
	private enum CodingKeys: String, CodingKey {
		case id, manufacturer, model, mode, channels, symbolName, colorMixing, invertsPan, invertsTilt, panDegrees, tiltDegrees
	}
}
