import Foundation

nonisolated struct Levels: Sendable, Equatable {
	private(set) var lights: [String: [Int: UInt8]] = [:]
	
	init() {}
	
	init?(_ data: Data) {
		var reader = ByteReader(data)
		
		while !reader.isAtEnd {
			guard let (width, light) = reader.identifier(), width <= 64, let mask = reader.bytes(width) else { return nil }
			var slots = [Int: UInt8](minimumCapacity: mask.reduce(0) { $0 + $1.nonzeroBitCount })
			
			for (index, bits) in mask.enumerated() {
				for bit in 0..<8 where bits & (1 << bit) != 0 {
					guard let value = reader.byte() else { return nil }
					slots[index * 8 + bit + 1] = value
				}
			}
			
			guard !slots.isEmpty else { return nil }
			lights[light] = slots
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
	
	var slotCount: Int { lights.values.reduce(0) { $0 + $1.count } }
	
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
		return FeatureGroup.allCases.filter { group in type.channels(in: group).contains { $0.offsets.contains(where: { slots[$0] != nil }) } }
	}
}
