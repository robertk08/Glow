import SwiftData
import SwiftUI

nonisolated struct CustomChannel: Codable, Hashable, Identifiable, Sendable {
	var id = UUID()
	var role = ChannelRole.custom
	var name = ""
	var defaultValue: UInt8 = 0
	var isFine = false
	var ranges: [ChannelRange] = []
	
	private enum CodingKeys: String, CodingKey {
		case id, role, name, defaultValue, isFine, ranges
	}
	
	init(role: ChannelRole, name: String = "") {
		self.role = role
		self.name = name
	}
	
	init(from decoder: any Decoder) throws {
		let container = try decoder.container(keyedBy: CodingKeys.self)
		id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
		role = try container.decodeIfPresent(ChannelRole.self, forKey: .role) ?? .custom
		name = try container.decodeIfPresent(String.self, forKey: .name) ?? ""
		defaultValue = try container.decodeIfPresent(UInt8.self, forKey: .defaultValue) ?? 0
		isFine = try container.decodeIfPresent(Bool.self, forKey: .isFine) ?? false
		ranges = try container.decodeIfPresent([ChannelRange].self, forKey: .ranges) ?? []
	}
	
	var title: String { name.isEmpty ? role.name : name }
	
	var summary: String {
		var parts: [String] = []
		if !name.isEmpty { parts.append(role.name) }
		if isFine { parts.append("16-bit fine") }
		if defaultValue != 0 { parts.append("starts at \(defaultValue)") }
		
		if ranges.isEmpty {
			parts.append("no ranges")
		} else if ranges.count == 1 {
			parts.append("1 range")
		} else {
			parts.append("\(ranges.count) ranges")
		}
		
		return parts.joined(separator: " · ")
	}
}

@Model
final class CustomProfile {
	var identifier: String = UUID().uuidString
	var name: String = ""
	var symbol: String = "lightbulb"
	var channelList: [CustomChannel] = []
	var createdAt: Date = Date.now
	var isSubtractive: Bool = false
	
	init(name: String, symbol: String, channels: [CustomChannel], isSubtractive: Bool) {
		identifier = "custom-\(UUID().uuidString)"
		self.name = name
		self.symbol = symbol
		channelList = channels
		self.isSubtractive = isSubtractive
		createdAt = .now
	}
	
	var channels: [ProfileChannel] {
		var channels: [ProfileChannel] = []
		
		for (index, channel) in channelList.enumerated() {
			channels.append(ProfileChannel(offset: index + 1, role: channel.role, name: channel.title, isFine: channel.isFine, defaultValue: channel.defaultValue, ranges: channel.ranges))
		}
		
		return channels
	}
	
	var profile: FixtureProfile {
		FixtureProfile(id: identifier, model: name, mode: "\(channelList.count) channel", channels: channels, symbol: symbol, mixing: isSubtractive ? .subtractive : .additive)
	}
}
