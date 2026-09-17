import Foundation

nonisolated struct FixtureParameter: Identifiable, Hashable, Sendable {
	var coarse: ProfileChannel
	var fine: ProfileChannel?
	
	var id: Int { coarse.offset }
	var name: String { coarse.name }
	var role: ChannelRole { coarse.role }
	var ranges: [ChannelRange] { coarse.ranges }
	var maximum: Int { fine != nil ? 65535 : 255 }
	var isBanded: Bool { ranges.count > 1 }
	var neutral: Double { Double(coarse.defaultValue) * (fine == nil ? 1 : 256) }
}
