import Foundation

nonisolated enum Identifier {
	static func fresh() -> String {
		var text = ""
		
		for _ in 0..<8 {
			text += String(format: "%02x", UInt8.random(in: .min ... .max))
		}
		
		return text
	}
}
