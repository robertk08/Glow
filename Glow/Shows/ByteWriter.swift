import Foundation

nonisolated struct ByteWriter {
	private(set) var data = Data()
	
	mutating func byte(_ value: UInt8) {
		data.append(value)
	}
	
	mutating func bytes(_ values: [UInt8]) {
		data.append(contentsOf: values)
	}
	
	mutating func number(_ value: Int) {
		var rest = UInt(max(0, value))
		
		while rest >= 0x80 {
			data.append(UInt8(rest & 0x7F) | 0x80)
			rest >>= 7
		}
		
		data.append(UInt8(rest))
	}
	
	mutating func tenths(_ seconds: Double) {
		number(Int((seconds * 10).rounded()))
	}
	
	mutating func double(_ value: Double) {
		var bits = value.bitPattern
		
		for _ in 0..<8 {
			data.append(UInt8(bits & 0xFF))
			bits >>= 8
		}
	}
	
	mutating func order(_ value: Double) {
		let steps = value * 256
		
		guard steps >= 0, steps < 8_000_000_000, steps == steps.rounded() else {
			number(1)
			double(value)
			return
		}
		
		number(Int(steps) << 1)
	}
	
	mutating func text(_ value: String) {
		let bytes = Array(value.utf8)
		number(bytes.count)
		data.append(contentsOf: bytes)
	}
	
	mutating func identifier(_ value: String, tag: Int) {
		guard let packed = Identifier.value(value) else {
			number(tag << 2 | 2)
			text(value)
			return
		}
		
		number(tag << 2 | (packed.short ? 1 : 0))
		
		for shift in stride(from: 56, through: 0, by: -8) {
			data.append(UInt8(truncatingIfNeeded: packed.value >> UInt64(shift)))
		}
	}
}
