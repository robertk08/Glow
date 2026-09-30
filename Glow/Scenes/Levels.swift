import Foundation

nonisolated struct Levels: Sendable, Equatable {
	private(set) var lights: [String: [Int: UInt8]] = [:]
	
	init() {}
	
	init?(_ data: Data) {
		var lights: [String: [Int: UInt8]] = [:]
		
		let isRead = Self.read(data) { light, mask, values in
			var slots = [Int: UInt8](minimumCapacity: values.count)
			Self.visit(mask, values) { slots[$0] = $1 }
			lights[light] = slots
		}
		
		guard isRead else { return nil }
		self.lights = lights
	}
	
	@discardableResult static func read(_ data: Data, _ light: (String, [UInt8], [UInt8]) -> Void) -> Bool {
		var reader = ByteReader(data)
		
		while !reader.isAtEnd {
			guard let (width, identifier) = reader.identifier(), width <= 64, let mask = reader.bytes(width) else { return false }
			let count = mask.reduce(0) { $0 + $1.nonzeroBitCount }
			guard count > 0, let values = reader.bytes(count) else { return false }
			light(identifier, mask, values)
		}
		
		return true
	}
	
	static func visit(_ mask: [UInt8], _ values: [UInt8], _ slot: (Int, UInt8) -> Void) {
		var next = 0
		
		for (index, bits) in mask.enumerated() {
			for bit in 0..<8 where bits & (1 << bit) != 0 {
				slot(index * 8 + bit + 1, values[next])
				next += 1
			}
		}
	}
	
	var data: Data {
		var writer = ByteWriter()
		
		for light in lights.keys.sorted() {
			guard let slots = lights[light], let last = slots.keys.max() else { continue }
			var mask = [UInt8](repeating: 0, count: (last + 7) / 8)
			
			for slot in slots.keys {
				mask[(slot - 1) / 8] |= 1 << ((slot - 1) % 8)
			}
			
			writer.identifier(light, tag: mask.count)
			writer.bytes(mask)
			writer.bytes(slots.keys.sorted().compactMap { slots[$0] })
		}
		
		return writer.data
	}
	
	var isEmpty: Bool { lights.isEmpty }
	
	mutating func set(_ value: UInt8, slot: Int, of light: String) {
		guard (1...Universe.channelCount).contains(slot) else { return }
		lights[light, default: [:]][slot] = value
	}
	
	func merging(_ newer: Levels) -> Levels {
		var merged = self
		
		for (light, slots) in newer.lights {
			merged.lights[light, default: [:]].merge(slots) { _, fresh in fresh }
		}
		
		return merged
	}
	
	func removing(_ light: String) -> Levels {
		var trimmed = self
		trimmed.lights[light] = nil
		return trimmed
	}
	
	func features(of light: String, type: FixtureType?) -> [FeatureGroup] {
		guard let slots = lights[light], let type else { return [] }
		return FeatureGroup.allCases.filter { group in type.channels(storedWith: group).contains { $0.offsets.contains(where: { slots[$0] != nil }) } }
	}
}
