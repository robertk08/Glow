import Foundation

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
