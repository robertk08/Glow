import Foundation

nonisolated struct ChannelFunction: Codable, Hashable, Sendable, Identifiable {
	nonisolated enum Kind: String, Codable, Sendable {
		case setting, proportional
	}
	
	nonisolated enum Purpose: String, Codable, Sendable {
		case dim, open, closed, release
	}
	
	var from: UInt8
	var to: UInt8
	var label: String
	var kind: Kind = .setting
	var purpose: Purpose?
	var unit: PhysicalUnit?
	var physicalFrom: Double?
	var physicalTo: Double?
	var requiresConfirmation = false
	var holdSeconds: Double?
	var colors: [String] = []
	var sets: [ChannelSet] = []
	
	private let uid = Identity()
	
	var id: UUID { uid.value }
	var midpoint: UInt8 { UInt8((Int(from) + Int(to)) / 2) }
	var swatch: [LightColor] { colors.compactMap(LightColor.init(hex:)) }
	
	func contains(_ value: UInt8) -> Bool { (from...to).contains(value) }
	
	func set(containing value: UInt8) -> ChannelSet? {
		sets.first { $0.contains(value) }
	}
	
	func physical(at value: UInt8) -> String? {
		guard let unit, let physicalFrom else { return nil }
		guard let physicalTo, to > from else { return unit.label(physicalFrom) }
		let share = Double(value - from) / Double(to - from)
		return unit.label(physicalFrom + (physicalTo - physicalFrom) * share)
	}
	
	init(from: UInt8, to: UInt8, label: String, kind: Kind = .setting, purpose: Purpose? = nil) {
		self.from = min(from, to)
		self.to = max(from, to)
		self.label = label
		self.kind = kind
		self.purpose = purpose
	}
	
	init(from decoder: any Decoder) throws {
		let container = try decoder.container(keyedBy: CodingKeys.self)
		let start = try container.decode(UInt8.self, forKey: .from)
		let end = try container.decode(UInt8.self, forKey: .to)
		from = min(start, end)
		to = max(start, end)
		label = try container.decode(String.self, forKey: .label)
		kind = try container.decodeIfPresent(Kind.self, forKey: .kind) ?? .setting
		purpose = try container.decodeIfPresent(Purpose.self, forKey: .purpose)
		unit = try container.decodeIfPresent(PhysicalUnit.self, forKey: .unit)
		physicalFrom = try container.decodeIfPresent(Double.self, forKey: .physicalFrom)
		physicalTo = try container.decodeIfPresent(Double.self, forKey: .physicalTo)
		requiresConfirmation = try container.decodeIfPresent(Bool.self, forKey: .requiresConfirmation) ?? false
		holdSeconds = try container.decodeIfPresent(Double.self, forKey: .holdSeconds)
		colors = try container.decodeIfPresent([String].self, forKey: .colors) ?? []
		sets = try container.decodeIfPresent([ChannelSet].self, forKey: .sets) ?? []
	}
	
	func encode(to encoder: any Encoder) throws {
		var container = encoder.container(keyedBy: CodingKeys.self)
		try container.encode(from, forKey: .from)
		try container.encode(to, forKey: .to)
		try container.encode(label, forKey: .label)
		if kind != .setting { try container.encode(kind, forKey: .kind) }
		try container.encodeIfPresent(purpose, forKey: .purpose)
		try container.encodeIfPresent(unit, forKey: .unit)
		try container.encodeIfPresent(physicalFrom, forKey: .physicalFrom)
		try container.encodeIfPresent(physicalTo, forKey: .physicalTo)
		if requiresConfirmation { try container.encode(true, forKey: .requiresConfirmation) }
		try container.encodeIfPresent(holdSeconds, forKey: .holdSeconds)
		if !colors.isEmpty { try container.encode(colors, forKey: .colors) }
		if !sets.isEmpty { try container.encode(sets, forKey: .sets) }
	}
	
	private enum CodingKeys: String, CodingKey {
		case from, to, label, kind, purpose, unit, physicalFrom, physicalTo, requiresConfirmation, holdSeconds, colors, sets
	}
}
