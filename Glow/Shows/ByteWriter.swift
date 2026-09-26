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
	
	mutating func text(_ value: String) {
		let bytes = Array(value.utf8)
		number(bytes.count)
		data.append(contentsOf: bytes)
	}
	
	mutating func identifier(_ value: String, tag: Int) {
		let nibbles = value.utf8.map { digit -> UInt8? in
			switch digit {
			case 48...57: digit - 48
			case 97...102: digit - 87
			default: nil
			}
		}
		let isPacked = nibbles.count == 16 && nibbles.allSatisfy { $0 != nil }
		number(tag << 1 | (isPacked ? 0 : 1))
		
		guard isPacked else {
			text(value)
			return
		}
		
		for index in stride(from: 0, to: 16, by: 2) {
			data.append((nibbles[index] ?? 0) << 4 | (nibbles[index + 1] ?? 0))
		}
	}
}
