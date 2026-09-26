import Foundation

nonisolated struct ByteReader {
	private static let digits = Array("0123456789abcdef".utf8)
	
	private let bytes: [UInt8]
	private var cursor = 0
	
	init(_ data: Data) {
		bytes = [UInt8](data)
	}
	
	var isAtEnd: Bool { cursor >= bytes.count }
	
	var rest: Data { Data(bytes[min(cursor, bytes.count)...]) }
	
	mutating func byte() -> UInt8? {
		guard cursor < bytes.count else { return nil }
		cursor += 1
		return bytes[cursor - 1]
	}
	
	mutating func bytes(_ count: Int) -> [UInt8]? {
		guard count >= 0, cursor + count <= bytes.count else { return nil }
		cursor += count
		return Array(bytes[(cursor - count)..<cursor])
	}
	
	mutating func number() -> Int? {
		var value = 0
		
		for shift in stride(from: 0, to: 35, by: 7) {
			guard let next = byte() else { return nil }
			value |= Int(next & 0x7F) << shift
			if next < 0x80 { return value }
		}
		
		return nil
	}
	
	mutating func tenths() -> Double? {
		number().map { Double($0) / 10 }
	}
	
	mutating func double() -> Double? {
		guard let raw = bytes(8) else { return nil }
		var bits: UInt64 = 0
		
		for (index, value) in raw.enumerated() {
			bits |= UInt64(value) << (8 * index)
		}
		
		return Double(bitPattern: bits)
	}
	
	mutating func text() -> String? {
		guard let count = number(), let raw = bytes(count) else { return nil }
		return String(bytes: raw, encoding: .utf8)
	}
	
	mutating func identifier() -> (tag: Int, value: String)? {
		guard let header = number() else { return nil }
		
		guard header & 1 == 0 else {
			guard let value = text(), !value.isEmpty else { return nil }
			return (header >> 1, value)
		}
		
		guard cursor + 8 <= bytes.count else { return nil }
		let start = cursor
		cursor += 8
		
		return (header >> 1, String(unsafeUninitializedCapacity: 16) { text in
			for index in 0..<8 {
				text[index * 2] = Self.digits[Int(bytes[start + index] >> 4)]
				text[index * 2 + 1] = Self.digits[Int(bytes[start + index] & 0x0F)]
			}
			
			return 16
		})
	}
}
