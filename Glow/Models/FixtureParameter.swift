import Foundation

struct FixtureParameter: Identifiable {
	var coarse: ProfileChannel
	var fine: ProfileChannel?
	
	var id: Int { coarse.offset }
	var name: String { coarse.name }
	var role: ChannelRole { coarse.role }
	var ranges: [ChannelRange] { coarse.ranges }
	var isWide: Bool { fine != nil }
	var maximum: Int { isWide ? 65535 : 255 }
	var isBanded: Bool { ranges.count > 1 }
}
