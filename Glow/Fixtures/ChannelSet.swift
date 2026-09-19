import Foundation

nonisolated struct ChannelSet: Codable, Hashable, Sendable, Identifiable {
	var from: UInt8
	var to: UInt8
	var label: String
	var colors: [String] = []
	
	var id: String { "\(from)-\(to)" }
	var midpoint: UInt8 { UInt8((Int(from) + Int(to)) / 2) }
	var swatch: [LightColor] { colors.compactMap(LightColor.init(hex:)) }
	
	func contains(_ value: UInt8) -> Bool { (from...to).contains(value) }
	
	init(from: UInt8, to: UInt8, label: String, colors: [String] = []) {
		self.from = min(from, to)
		self.to = max(from, to)
		self.label = label
		self.colors = colors
	}
	
	init(from decoder: any Decoder) throws {
		let container = try decoder.container(keyedBy: CodingKeys.self)
		self.init(from: try container.decode(UInt8.self, forKey: .from), to: try container.decode(UInt8.self, forKey: .to), label: try container.decode(String.self, forKey: .label), colors: try container.decodeIfPresent([String].self, forKey: .colors) ?? [])
	}
	
	func encode(to encoder: any Encoder) throws {
		var container = encoder.container(keyedBy: CodingKeys.self)
		try container.encode(from, forKey: .from)
		try container.encode(to, forKey: .to)
		try container.encode(label, forKey: .label)
		if !colors.isEmpty { try container.encode(colors, forKey: .colors) }
	}
	
	private enum CodingKeys: String, CodingKey {
		case from, to, label, colors
	}
}
