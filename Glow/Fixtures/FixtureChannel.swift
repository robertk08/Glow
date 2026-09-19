import Foundation

nonisolated struct FixtureChannel: Codable, Hashable, Sendable, Identifiable {
	nonisolated struct Dependency: Codable, Hashable, Sendable {
		var offset: Int
		var from: UInt8
		var to: UInt8
		
		func contains(_ value: UInt8) -> Bool { (from...to).contains(value) }
	}
	
	var offset: Int
	var fineOffset: Int?
	var attribute: Attribute = .custom
	var label: String?
	var defaultValue: UInt8 = 0
	var fineDefaultValue: UInt8 = 0
	var highlightValue: UInt8?
	var enabledBy: Dependency?
	var functions: [ChannelFunction] = []
	
	var id: Int { offset }
	var name: String { label ?? attribute.name }
	var isWide: Bool { fineOffset != nil }
	var maximum: Int { isWide ? 65535 : 255 }
	var neutral: Int { Int(defaultValue) * (isWide ? 256 : 1) + Int(fineDefaultValue) }
	var offsets: [Int] { [offset] + (fineOffset.map { [$0] } ?? []) }
	var isBanded: Bool { functions.count > 1 }
	
	func function(containing value: UInt8) -> ChannelFunction? {
		functions.first { $0.contains(value) }
	}
	
	var highlight: UInt8? {
		if let highlightValue { return highlightValue }
		if attribute == .dimmer { return 255 }
		if let open = functions.first(where: { $0.purpose == .open }) { return open.from }
		if let release = functions.first(where: { $0.purpose == .release }) { return release.midpoint }
		return nil
	}
	
	var summary: String {
		var parts: [String] = []
		if label != nil { parts.append(attribute.name) }
		if isWide { parts.append("16-bit") }
		if defaultValue != 0 { parts.append("starts at \(defaultValue)") }
		if let highlightValue { parts.append("highlight \(highlightValue)") }
		parts.append(functions.isEmpty ? "no ranges" : "^[\(functions.count) range](inflect: true)")
		return parts.joined(separator: " · ")
	}
	
	var addressLabel: String {
		isWide ? "\(offset)+\(fineOffset ?? 0)" : "\(offset)"
	}
	
	init(offset: Int, attribute: Attribute, label: String? = nil, fineOffset: Int? = nil, defaultValue: UInt8 = 0, fineDefaultValue: UInt8 = 0, highlightValue: UInt8? = nil, enabledBy: Dependency? = nil, functions: [ChannelFunction] = []) {
		self.offset = offset
		self.fineOffset = fineOffset
		self.attribute = attribute
		self.label = label
		self.defaultValue = defaultValue
		self.fineDefaultValue = fineDefaultValue
		self.highlightValue = highlightValue
		self.enabledBy = enabledBy
		self.functions = functions
	}
	
	init(from decoder: any Decoder) throws {
		let container = try decoder.container(keyedBy: CodingKeys.self)
		offset = try container.decode(Int.self, forKey: .offset)
		fineOffset = try container.decodeIfPresent(Int.self, forKey: .fineOffset)
		attribute = try container.decodeIfPresent(Attribute.self, forKey: .attribute) ?? .custom
		label = try container.decodeIfPresent(String.self, forKey: .label)
		defaultValue = try container.decodeIfPresent(UInt8.self, forKey: .defaultValue) ?? 0
		fineDefaultValue = try container.decodeIfPresent(UInt8.self, forKey: .fineDefaultValue) ?? 0
		highlightValue = try container.decodeIfPresent(UInt8.self, forKey: .highlightValue)
		enabledBy = try container.decodeIfPresent(Dependency.self, forKey: .enabledBy)
		functions = try container.decodeIfPresent([ChannelFunction].self, forKey: .functions) ?? []
	}
	
	func encode(to encoder: any Encoder) throws {
		var container = encoder.container(keyedBy: CodingKeys.self)
		try container.encode(offset, forKey: .offset)
		try container.encodeIfPresent(fineOffset, forKey: .fineOffset)
		try container.encode(attribute, forKey: .attribute)
		try container.encodeIfPresent(label, forKey: .label)
		if defaultValue != 0 { try container.encode(defaultValue, forKey: .defaultValue) }
		if fineDefaultValue != 0 { try container.encode(fineDefaultValue, forKey: .fineDefaultValue) }
		try container.encodeIfPresent(highlightValue, forKey: .highlightValue)
		try container.encodeIfPresent(enabledBy, forKey: .enabledBy)
		if !functions.isEmpty { try container.encode(functions, forKey: .functions) }
	}
	
	private enum CodingKeys: String, CodingKey {
		case offset, fineOffset, attribute, label, defaultValue, fineDefaultValue, highlightValue, enabledBy, functions
	}
}
