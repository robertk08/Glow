import Foundation

nonisolated struct Levels: Sendable, Equatable {
	private(set) var lights: [String: [Int: UInt8]] = [:]
	
	init() {}
	
	init?(_ data: Data) {
		guard let lights = Self.read(data, keeping: true) else { return nil }
		self.lights = lights
	}
	
	static func isReadable(_ data: Data) -> Bool {
		read(data, keeping: false) != nil
	}
	
	private static func read(_ data: Data, keeping: Bool) -> [String: [Int: UInt8]]? {
		var reader = ByteReader(data)
		var lights: [String: [Int: UInt8]] = [:]
		
		while !reader.isAtEnd {
			guard let (width, light) = reader.identifier(), width <= 64, let mask = reader.bytes(width) else { return nil }
			let count = mask.reduce(0) { $0 + $1.nonzeroBitCount }
			guard count > 0, let values = reader.bytes(count) else { return nil }
			guard keeping else { continue }
			var slots = [Int: UInt8](minimumCapacity: count)
			var next = 0
			
			for (index, bits) in mask.enumerated() {
				for bit in 0..<8 where bits & (1 << bit) != 0 {
					slots[index * 8 + bit + 1] = values[next]
					next += 1
				}
			}
			
			lights[light] = slots
		}
		
		return lights
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
		return FeatureGroup.allCases.filter { group in type.channels(in: group).contains { $0.offsets.contains(where: { slots[$0] != nil }) } }
	}
}
