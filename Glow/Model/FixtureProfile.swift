import Foundation

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
	
	var parameters: [FixtureParameter] {
		var parameters: [FixtureParameter] = []
		
		for channel in channels.sorted(by: { $0.offset < $1.offset }) where !channel.isFine {
			let next = channels.filter { !$0.isFine && $0.role == channel.role && $0.offset > channel.offset }.map(\.offset).min() ?? Int.max
			let fine = channels.first { $0.isFine && $0.role == channel.role && $0.offset > channel.offset && $0.offset < next }
			parameters.append(FixtureParameter(coarse: channel, fine: fine))
		}
		
		return parameters
	}
	
	var emitterChannels: [ProfileChannel] {
		channels.filter { $0.role.isEmitter && !$0.isFine }
	}
	
	var emitters: [ChannelRole] { emitterChannels.map(\.role) }
	
	var movesHead: Bool { channel(.pan) != nil && channel(.tilt) != nil }
	
	var abilities: [String] {
		var found: [String] = []
		if dims { found.append("Dimmer") }
		if mixesColor { found.append(mixing == .subtractive ? "CMY" : "Color") }
		if channel(.colorWheel) != nil || channel(.colorMacro) != nil { found.append("Color wheel") }
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
		for channel in channels where channel.offset > 0 && channel.offset <= channelCount {
			values[channel.offset - 1] = channel.defaultValue
		}
		return values
	}
	
	var dimming: Dimming {
		if let dedicated = channel(.intensity) {
			return .channel(dedicated)
		}
		if let shutter = channel(.shutter), let band = shutter.ranges.first(where: { $0.kind == .proportional && $0.label.localizedCaseInsensitiveContains("dim") }) {
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
