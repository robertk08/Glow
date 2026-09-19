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
	
	static func mixesWithFlags(_ channels: [CustomChannel]) -> Bool {
		Set(Emitter.flags).isSubset(of: Set(channels.filter { !$0.isFine }.map(\.role)))
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
