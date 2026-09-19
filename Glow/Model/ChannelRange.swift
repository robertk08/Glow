import Foundation

nonisolated struct ChannelRange: Codable, Hashable, Sendable, Identifiable {
	nonisolated enum Kind: String, Codable, Sendable {
		case discrete, proportional
	}
	
	var from: UInt8
	var to: UInt8
	var label: String
	var kind: Kind = .discrete
	var requiresConfirmation = false
	var releasesMix = false
	var holdSeconds: Double?
	
	var id: String { "\(from)-\(to)" }
	var midpoint: UInt8 { UInt8((Int(from) + Int(to)) / 2) }
	
	func contains(_ value: UInt8) -> Bool { (from...to).contains(value) }
	
	private enum CodingKeys: String, CodingKey {
		case from, to, label, kind, requiresConfirmation, releasesMix, holdSeconds
	}
	
	init(from: UInt8, to: UInt8, label: String, kind: Kind = .discrete) {
		self.from = from
		self.to = to
		self.label = label
		self.kind = kind
	}
	
	init(from decoder: any Decoder) throws {
		let container = try decoder.container(keyedBy: CodingKeys.self)
		let start = try container.decode(UInt8.self, forKey: .from)
		let end = try container.decode(UInt8.self, forKey: .to)
		from = min(start, end)
		to = max(start, end)
		label = try container.decode(String.self, forKey: .label)
		kind = try container.decodeIfPresent(Kind.self, forKey: .kind) ?? .discrete
		requiresConfirmation = try container.decodeIfPresent(Bool.self, forKey: .requiresConfirmation) ?? false
		releasesMix = try container.decodeIfPresent(Bool.self, forKey: .releasesMix) ?? false
		holdSeconds = try container.decodeIfPresent(Double.self, forKey: .holdSeconds)
	}
}
