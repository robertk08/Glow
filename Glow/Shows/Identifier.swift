import Foundation

nonisolated enum Identifier {
	private static let hex = Array("0123456789abcdef".utf8)
	private static let url = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_".utf8)
	
	static func fresh() -> String {
		text(UInt64.random(in: .min ... .max), short: true)
	}
	
	static func text(_ value: UInt64, short: Bool) -> String {
		guard short else {
			return String(unsafeUninitializedCapacity: 16) { text in
				for index in 0..<16 {
					text[index] = hex[Int((value >> (60 - 4 * UInt64(index))) & 15)]
				}
				
				return 16
			}
		}
		
		return String(unsafeUninitializedCapacity: 11) { text in
			for index in 0..<10 {
				text[index] = url[Int((value >> (58 - 6 * UInt64(index))) & 63)]
			}
			
			text[10] = url[Int((value << 2) & 63)]
			return 11
		}
	}
	
	static func value(_ text: String) -> (value: UInt64, short: Bool)? {
		let digits = Array(text.utf8)
		var value: UInt64 = 0
		
		if digits.count == 16 {
			for digit in digits {
				guard let nibble = hex.firstIndex(of: digit) else { return nil }
				value = value << 4 | UInt64(nibble)
			}
			
			return (value, false)
		}
		
		guard digits.count == 11 else { return nil }
		
		for digit in digits.prefix(10) {
			guard let sextet = url.firstIndex(of: digit) else { return nil }
			value = value << 6 | UInt64(sextet)
		}
		
		guard let last = url.firstIndex(of: digits[10]), last & 3 == 0 else { return nil }
		return (value << 4 | UInt64(last >> 2), true)
	}
	
	static func unusedName(_ base: String, among names: [String]) -> String {
		let taken = Set(names)
		guard taken.contains(base) else { return base }
		var index = 2
		
		while taken.contains("\(base) \(index)") {
			index += 1
		}
		
		return "\(base) \(index)"
	}
}
