import Foundation

nonisolated struct FixtureMode: Codable, Hashable, Sendable, Identifiable {
	nonisolated enum Dimming: Sendable, Equatable {
		case channel(FixtureChannel)
		case band(FixtureChannel, from: UInt8, to: UInt8, open: UInt8?)
		case emitters([FixtureChannel])
		case none
	}
	
	var id: String
	var typeID: String
	var manufacturer: String
	var model: String
	var mode: String
	var channels: [FixtureChannel]
	var symbol: String
	var mixing: ColorMixing
	var invertsPan: Bool
	var invertsTilt: Bool
	var panDegrees: Double?
	var tiltDegrees: Double?
	
	var name: String { manufacturer.isEmpty ? model : "\(manufacturer) \(model)" }
	var channelCount: Int { channels.flatMap(\.offsets).max() ?? 0 }
	
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
	
	var abilities: [String] {
		var found: [String] = []
		if dims { found.append("Dimmer") }
		if mixesColor { found.append(mixing == .subtractive ? "CMY" : "Color") }
		if movesHead { found.append("Moving head") }
		
		for attribute in [Attribute.colorWheel, .colorMacro, .shutter, .gobo, .gobo2, .prism, .zoom, .focus, .iris, .frost] where channel(attribute) != nil {
			found.append(attribute.name)
		}
		
		return found
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
}
